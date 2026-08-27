#include <windows.h>

#include <atomic>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "ipc_readonly_listener.h"

namespace {

HANDLE ConnectLocalClient(const std::wstring& pipe_name) noexcept {
  const ULONGLONG deadline = GetTickCount64() + 5000;
  while (GetTickCount64() < deadline) {
    HANDLE client = CreateFileW(pipe_name.c_str(), GENERIC_READ | GENERIC_WRITE,
                                0, nullptr, OPEN_EXISTING, 0, nullptr);
    if (client != INVALID_HANDLE_VALUE) {
      return client;
    }

    const DWORD error = GetLastError();
    if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PIPE_BUSY) {
      return INVALID_HANDLE_VALUE;
    }
    Sleep(10);
  }
  SetLastError(ERROR_TIMEOUT);
  return INVALID_HANDLE_VALUE;
}

}  // namespace

int wmain() {
  const std::wstring pipe_name =
      L"\\\\.\\pipe\\QuantaraExecutionService.listener-self-test." +
      std::to_wstring(GetCurrentProcessId());
  HANDLE stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE ready_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (stop_event == nullptr || ready_event == nullptr) {
    if (stop_event != nullptr) {
      CloseHandle(stop_event);
    }
    if (ready_event != nullptr) {
      CloseHandle(ready_event);
    }
    std::wcerr << L"Could not create listener lifecycle events.\n";
    return 1;
  }

  std::atomic<quantara::ServiceSafetyState> safety_state{
      quantara::ServiceSafetyState::kDisarmed};
  std::atomic<bool> listener_ok{false};
  std::thread listener([&]() {
    listener_ok.store(quantara::RunReadOnlyStatusListener(
                          stop_event, pipe_name, safety_state, ready_event),
                      std::memory_order_relaxed);
  });

  const bool became_ready =
      WaitForSingleObject(ready_event, 5000) == WAIT_OBJECT_0;
  HANDLE client = became_ready ? ConnectLocalClient(pipe_name)
                               : INVALID_HANDLE_VALUE;
  bool client_ok = client != INVALID_HANDLE_VALUE;
  if (client_ok) {
    DWORD message_mode = PIPE_READMODE_MESSAGE;
    client_ok =
        SetNamedPipeHandleState(client, &message_mode, nullptr, nullptr) == TRUE;
  }

  const std::string request =
      "{\"protocolVersion\":1,\"requestId\":\"listener-status-1\",\"kind\":\"statusRequest\",\"payload\":{}}";
  const std::string expected =
      "{\"protocolVersion\":1,\"requestId\":\"listener-status-1\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"disarmed\",\"entryAuthority\":false}}";
  if (client_ok) {
    DWORD written = 0;
    client_ok =
        WriteFile(client, request.data(), static_cast<DWORD>(request.size()),
                  &written, nullptr) == TRUE &&
        written == request.size();
  }

  if (client_ok) {
    std::vector<char> response(64 * 1024);
    DWORD read = 0;
    client_ok =
        ReadFile(client, response.data(), static_cast<DWORD>(response.size()),
                 &read, nullptr) == TRUE &&
        read > 0;
    if (client_ok) {
      response.resize(read);
      client_ok = std::string(response.begin(), response.end()) == expected;
    }
  }

  if (client != INVALID_HANDLE_VALUE) {
    CloseHandle(client);
  }

  SetEvent(stop_event);
  CancelSynchronousIo(listener.native_handle());
  listener.join();
  CloseHandle(ready_event);
  CloseHandle(stop_event);

  if (!became_ready || !client_ok ||
      !listener_ok.load(std::memory_order_relaxed)) {
    std::wcerr << L"SCM-safe read-only listener self-test failed.\n";
    return 1;
  }

  std::wcout << L"Quantara Windows read-only listener self-test passed.\n";
  return 0;
}
