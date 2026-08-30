#include <windows.h>

#include <atomic>
#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "ipc_readonly_session.h"
#include "local_pipe_security.h"

namespace {

quantara::ExistingPositionMutationExecutionResult HandleClose(
    const quantara::ManagementOnlyRequest& request) noexcept {
  if (request.kind !=
          quantara::ManagementOnlyRequestKind::kCloseExistingPosition ||
      request.position_id != "123456789") {
    return {false, false, false, "unexpectedRequest"};
  }
  return {true, true, true, "confirmedByFreshExchangeTruth"};
}

}  // namespace

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
  const std::string management_request =
      "{\"protocolVersion\":1,\"requestId\":\"close-roundtrip-1\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"123456789\"}}";
  const std::string management_expected =
      "{\"protocolVersion\":1,\"requestId\":\"close-roundtrip-1\",\"kind\":\"managementResult\",\"payload\":{\"completed\":true,\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";

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

    auto round_trip = [&](const std::string& outbound,
                          const std::string& expected_response) {
      DWORD written = 0;
      if (!WriteFile(handle, outbound.data(), static_cast<DWORD>(outbound.size()),
                     &written, nullptr) ||
          written != outbound.size()) {
        return false;
      }

      std::vector<char> response(64 * 1024);
      DWORD read = 0;
      if (!ReadFile(handle, response.data(), static_cast<DWORD>(response.size()),
                    &read, nullptr) ||
          read == 0) {
        return false;
      }
      response.resize(read);
      return std::string(response.begin(), response.end()) == expected_response;
    };

    const bool read_only_ok = round_trip(request, expected);
    const bool management_ok =
        read_only_ok && round_trip(management_request, management_expected);
    client_ok.store(management_ok, std::memory_order_relaxed);
    CloseHandle(handle);
  });

  const BOOL connected = ConnectNamedPipe(pipe, nullptr);
  const DWORD connect_error = connected ? ERROR_SUCCESS : GetLastError();
  const bool connection_ok =
      connected == TRUE || connect_error == ERROR_PIPE_CONNECTED;

  quantara::RequestReplayGuard replay_guard;
  const bool read_only_server_ok =
      connection_ok && quantara::ProcessAuthenticatedFrame(
                           pipe, quantara::ServiceSafetyState::kDisarmed,
                           quantara::CredentialReadiness::kReady, replay_guard,
                           HandleClose);
  const bool management_server_ok =
      read_only_server_ok && quantara::ProcessAuthenticatedFrame(
                                 pipe,
                                 quantara::ServiceSafetyState::kManageExistingOnly,
                                 quantara::CredentialReadiness::kReady,
                                 replay_guard, HandleClose);

  FlushFileBuffers(pipe);
  DisconnectNamedPipe(pipe);
  CloseHandle(pipe);
  client.join();

  if (!read_only_server_ok || !management_server_ok ||
      !client_ok.load(std::memory_order_relaxed) || replay_guard.size() != 2) {
    std::wcerr << L"Authenticated IPC session round trip failed.\n";
    return 1;
  }

  std::wcout << L"Quantara Windows authenticated session self-test passed.\n";
  return 0;
}
