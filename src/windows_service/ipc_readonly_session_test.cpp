#include <windows.h>

#include <atomic>
#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "ipc_readonly_session.h"
#include "local_pipe_security.h"

int wmain() {
  const std::wstring pipe_name =
      L"\\\\.\\pipe\\QuantaraExecutionService.session-self-test." +
      std::to_wstring(GetCurrentProcessId());
  HANDLE pipe = quantara::CreateLocalPipeServer(pipe_name);
  if (pipe == INVALID_HANDLE_VALUE) {
    std::wcerr << L"Could not create session self-test pipe.\n";
    return 1;
  }

  const std::string request =
      "{\"protocolVersion\":1,\"requestId\":\"status-roundtrip-1\",\"kind\":\"statusRequest\",\"payload\":{}}";
  const std::string expected =
      "{\"protocolVersion\":1,\"requestId\":\"status-roundtrip-1\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"disarmed\",\"entryAuthority\":false}}";

  std::atomic<bool> client_ok{false};
  std::thread client([&]() {
    if (!WaitNamedPipeW(pipe_name.c_str(), 5000)) {
      return;
    }
    HANDLE handle = CreateFileW(pipe_name.c_str(), GENERIC_READ | GENERIC_WRITE,
                                0, nullptr, OPEN_EXISTING, 0, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
      return;
    }
    DWORD message_mode = PIPE_READMODE_MESSAGE;
    if (!SetNamedPipeHandleState(handle, &message_mode, nullptr, nullptr)) {
      CloseHandle(handle);
      return;
    }

    DWORD written = 0;
    if (!WriteFile(handle, request.data(), static_cast<DWORD>(request.size()),
                   &written, nullptr) ||
        written != request.size()) {
      CloseHandle(handle);
      return;
    }

    std::vector<char> response(64 * 1024);
    DWORD read = 0;
    if (!ReadFile(handle, response.data(), static_cast<DWORD>(response.size()),
                  &read, nullptr) ||
        read == 0) {
      CloseHandle(handle);
      return;
    }
    response.resize(read);
    client_ok.store(std::string(response.begin(), response.end()) == expected,
                    std::memory_order_relaxed);
    CloseHandle(handle);
  });

  const BOOL connected = ConnectNamedPipe(pipe, nullptr);
  const DWORD connect_error = connected ? ERROR_SUCCESS : GetLastError();
  const bool connection_ok =
      connected == TRUE || connect_error == ERROR_PIPE_CONNECTED;

  quantara::RequestReplayGuard replay_guard;
  const bool server_ok =
      connection_ok && quantara::ProcessAuthenticatedReadOnlyFrame(
                           pipe, quantara::ServiceSafetyState::kDisarmed,
                           replay_guard);

  FlushFileBuffers(pipe);
  DisconnectNamedPipe(pipe);
  CloseHandle(pipe);
  client.join();

  if (!server_ok || !client_ok.load(std::memory_order_relaxed) ||
      replay_guard.size() != 1) {
    std::wcerr << L"Authenticated read-only IPC round trip failed.\n";
    return 1;
  }

  std::wcout << L"Quantara Windows read-only session self-test passed.\n";
  return 0;
}
