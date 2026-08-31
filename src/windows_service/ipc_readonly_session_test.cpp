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

quantara::ExistingPositionMutationExecutionResult HandleManagement(
    const quantara::ManagementOnlyRequest& request) noexcept {
  if (request.position_id != "123456789") {
    return {false, false, false, "unexpectedRequest"};
  }
  if (request.kind ==
          quantara::ManagementOnlyRequestKind::kCloseExistingPosition &&
      request.new_stop_price == 0.0) {
    return {true, true, true, "confirmedByFreshExchangeTruth"};
  }
  if (request.kind ==
          quantara::ManagementOnlyRequestKind::kTightenExistingStop &&
      request.new_stop_price == 65000.5) {
    return {true, true, true, "confirmedByFreshExchangeTruth"};
  }
  return {false, false, false, "unexpectedRequest"};
}

std::vector<std::uint8_t> Bytes(const std::string& value) {
  return std::vector<std::uint8_t>(value.begin(), value.end());
}

}  // namespace

int wmain() {
  const std::string invalid_zero_stop =
      "{\"protocolVersion\":1,\"requestId\":\"tighten-invalid-1\",\"kind\":\"tightenExistingStop\",\"payload\":{\"positionId\":\"123456789\",\"newStopPrice\":\"0\"}}";
  const std::string invalid_nan_stop =
      "{\"protocolVersion\":1,\"requestId\":\"tighten-invalid-2\",\"kind\":\"tightenExistingStop\",\"payload\":{\"positionId\":\"123456789\",\"newStopPrice\":\"nan\"}}";
  const std::string caller_selected_trigger =
      "{\"protocolVersion\":1,\"requestId\":\"tighten-invalid-3\",\"kind\":\"tightenExistingStop\",\"payload\":{\"positionId\":\"123456789\",\"newStopPrice\":\"65000.5\",\"slStopType\":\"LAST_PRICE\"}}";
  if (quantara::DecodeCanonicalManagementOnlyRequest(Bytes(invalid_zero_stop))
          .has_value() ||
      quantara::DecodeCanonicalManagementOnlyRequest(Bytes(invalid_nan_stop))
          .has_value() ||
      quantara::DecodeCanonicalManagementOnlyRequest(Bytes(caller_selected_trigger))
          .has_value()) {
    std::wcerr << L"Unsafe tighten-stop IPC frame was accepted.\n";
    return 1;
  }

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
  const std::string close_request =
      "{\"protocolVersion\":1,\"requestId\":\"close-roundtrip-1\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"123456789\"}}";
  const std::string close_expected =
      "{\"protocolVersion\":1,\"requestId\":\"close-roundtrip-1\",\"kind\":\"managementResult\",\"payload\":{\"completed\":true,\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";
  const std::string tighten_request =
      "{\"protocolVersion\":1,\"requestId\":\"tighten-roundtrip-1\",\"kind\":\"tightenExistingStop\",\"payload\":{\"positionId\":\"123456789\",\"newStopPrice\":\"65000.5\"}}";
  const std::string tighten_expected =
      "{\"protocolVersion\":1,\"requestId\":\"tighten-roundtrip-1\",\"kind\":\"managementResult\",\"payload\":{\"completed\":true,\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";

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
    const bool close_ok =
        read_only_ok && round_trip(close_request, close_expected);
    const bool tighten_ok =
        close_ok && round_trip(tighten_request, tighten_expected);
    client_ok.store(tighten_ok, std::memory_order_relaxed);
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
                           HandleManagement);
  const bool close_server_ok =
      read_only_server_ok && quantara::ProcessAuthenticatedFrame(
                                 pipe,
                                 quantara::ServiceSafetyState::kManageExistingOnly,
                                 quantara::CredentialReadiness::kReady,
                                 replay_guard, HandleManagement);
  const bool tighten_server_ok =
      close_server_ok && quantara::ProcessAuthenticatedFrame(
                             pipe,
                             quantara::ServiceSafetyState::kManageExistingOnly,
                             quantara::CredentialReadiness::kReady, replay_guard,
                             HandleManagement);

  FlushFileBuffers(pipe);
  DisconnectNamedPipe(pipe);
  CloseHandle(pipe);
  client.join();

  if (!read_only_server_ok || !close_server_ok || !tighten_server_ok ||
      !client_ok.load(std::memory_order_relaxed) || replay_guard.size() != 3) {
    std::wcerr << L"Authenticated IPC session round trip failed.\n";
    return 1;
  }

  std::wcout << L"Quantara Windows authenticated session self-test passed.\n";
  return 0;
}
