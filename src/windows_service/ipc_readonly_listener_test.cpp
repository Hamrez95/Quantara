#include <windows.h>

#include <atomic>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "ipc_readonly_listener.h"

namespace {

std::atomic<bool> g_management_handled{false};

quantara::ExistingPositionMutationExecutionResult HandleClose(
    const quantara::ManagementOnlyRequest& request) noexcept {
  if (request.kind !=
          quantara::ManagementOnlyRequestKind::kCloseExistingPosition ||
      request.position_id != "123456789") {
    return {false, false, false, "unexpectedRequest"};
  }
  g_management_handled.store(true, std::memory_order_relaxed);
  return {true, true, true, "confirmedByFreshExchangeTruth"};
}

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

bool RoundTrip(const std::wstring& pipe_name, const std::string& request,
               const std::string& expected) noexcept {
  HANDLE client = ConnectLocalClient(pipe_name);
  if (client == INVALID_HANDLE_VALUE) {
    return false;
  }

  DWORD message_mode = PIPE_READMODE_MESSAGE;
  bool ok = SetNamedPipeHandleState(client, &message_mode, nullptr, nullptr) == TRUE;
  if (ok) {
    DWORD written = 0;
    ok = WriteFile(client, request.data(), static_cast<DWORD>(request.size()),
                   &written, nullptr) == TRUE &&
         written == request.size();
  }

  if (ok) {
    std::vector<char> response(64 * 1024);
    DWORD read = 0;
    ok = ReadFile(client, response.data(), static_cast<DWORD>(response.size()),
                  &read, nullptr) == TRUE &&
         read > 0;
    if (ok) {
      response.resize(read);
      ok = std::string(response.begin(), response.end()) == expected;
    }
  }

  CloseHandle(client);
  return ok;
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
  std::atomic<quantara::CredentialReadiness> credential_readiness{
      quantara::CredentialReadiness::kReady};
  std::atomic<bool> listener_ok{false};
  std::thread listener([&]() {
    listener_ok.store(quantara::RunReadOnlyStatusListener(
                          stop_event, pipe_name, safety_state,
                          credential_readiness, ready_event, HandleClose),
                      std::memory_order_relaxed);
  });

  const bool became_ready =
      WaitForSingleObject(ready_event, 5000) == WAIT_OBJECT_0;

  const std::string status_request =
      "{\"protocolVersion\":1,\"requestId\":\"listener-status-1\",\"kind\":\"statusRequest\",\"payload\":{}}";
  const std::string status_expected =
      "{\"protocolVersion\":1,\"requestId\":\"listener-status-1\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"disarmed\",\"entryAuthority\":false}}";
  const bool status_ok =
      became_ready && RoundTrip(pipe_name, status_request, status_expected);

  safety_state.store(quantara::ServiceSafetyState::kManageExistingOnly,
                     std::memory_order_relaxed);
  const std::string management_request =
      "{\"protocolVersion\":1,\"requestId\":\"listener-close-1\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"123456789\"}}";
  const std::string management_expected =
      "{\"protocolVersion\":1,\"requestId\":\"listener-close-1\",\"kind\":\"managementResult\",\"payload\":{\"completed\":true,\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";
  const bool management_ok =
      status_ok && RoundTrip(pipe_name, management_request, management_expected);

  SetEvent(stop_event);
  CancelSynchronousIo(listener.native_handle());
  listener.join();
  CloseHandle(ready_event);
  CloseHandle(stop_event);

  if (!became_ready || !status_ok || !management_ok ||
      !g_management_handled.load(std::memory_order_relaxed) ||
      !listener_ok.load(std::memory_order_relaxed)) {
    std::wcerr << L"Authenticated status/control listener self-test failed.\n";
    return 1;
  }

  std::wcout << L"Quantara Windows authenticated listener self-test passed.\n";
  return 0;
}
