#include <windows.h>

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "credential_vault.h"
#include "ipc_readonly_listener.h"
#include "ipc_request_protocol.h"
#include "local_pipe_security.h"
#include "local_pipe_transport.h"
#include "network_change_monitor.h"

namespace {
constexpr wchar_t kServiceName[] = L"QuantaraExecutionService";
constexpr wchar_t kStatusPipeName[] =
    L"\\\\.\\pipe\\QuantaraExecutionService.status";

std::atomic<quantara::ServiceSafetyState> g_safety_state{
    quantara::ServiceSafetyState::kDisarmed};
SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status{};
HANDLE g_stop_event = nullptr;

quantara::ServiceSafetyState SafetyStateAfterPowerEvent(
    DWORD event_type) noexcept {
  switch (event_type) {
    case PBT_APMSUSPEND:
      return quantara::ServiceSafetyState::kInterrupted;
    case PBT_APMRESUMEAUTOMATIC:
    case PBT_APMRESUMECRITICAL:
    case PBT_APMRESUMESUSPEND:
      return quantara::ServiceSafetyState::kReconciliationRequired;
    default:
      return g_safety_state.load(std::memory_order_relaxed);
  }
}

void ReportServiceStatus(DWORD state, DWORD win32_exit_code = NO_ERROR,
                         DWORD wait_hint = 0) noexcept {
  if (g_status_handle == nullptr) {
    return;
  }

  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = win32_exit_code;
  g_status.dwWaitHint = wait_hint;
  g_status.dwControlsAccepted =
      state == SERVICE_RUNNING
          ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN |
                SERVICE_ACCEPT_POWEREVENT
          : 0;
  g_status.dwCheckPoint =
      state == SERVICE_START_PENDING || state == SERVICE_STOP_PENDING ? 1 : 0;

  SetServiceStatus(g_status_handle, &g_status);
}

DWORD WINAPI ServiceControlHandler(DWORD control, DWORD event_type,
                                   LPVOID /*event_data*/,
                                   LPVOID /*context*/) noexcept {
  switch (control) {
    case SERVICE_CONTROL_STOP:
    case SERVICE_CONTROL_SHUTDOWN:
      ReportServiceStatus(SERVICE_STOP_PENDING, NO_ERROR, 5000);
      if (g_stop_event != nullptr) {
        SetEvent(g_stop_event);
      }
      return NO_ERROR;
    case SERVICE_CONTROL_POWEREVENT:
      g_safety_state.store(SafetyStateAfterPowerEvent(event_type),
                           std::memory_order_relaxed);
      return NO_ERROR;
    default:
      return NO_ERROR;
  }
}

void WINAPI ServiceMain(DWORD /*argc*/, LPWSTR* /*argv*/) noexcept {
  g_status_handle =
      RegisterServiceCtrlHandlerExW(kServiceName, ServiceControlHandler, nullptr);
  if (g_status_handle == nullptr) {
    return;
  }

  ReportServiceStatus(SERVICE_START_PENDING, NO_ERROR, 5000);
  g_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_stop_event == nullptr) {
    ReportServiceStatus(SERVICE_STOPPED, GetLastError());
    return;
  }

  // A service start never grants execution authority. IPC is read-only and the
  // future reconciliation/execution layer must explicitly transition authority
  // through its own deterministic safety gates.
  g_safety_state.store(quantara::ServiceSafetyState::kDisarmed,
                       std::memory_order_relaxed);

  // Network lifecycle ownership belongs to the service boundary rather than
  // the IPC listener. This keeps the listener deterministic and ensures the
  // service fails closed before reporting Running when monitoring cannot be
  // registered with Windows.
  quantara::NetworkChangeMonitor network_monitor(g_safety_state);
  if (!network_monitor.Start()) {
    CloseHandle(g_stop_event);
    g_stop_event = nullptr;
    ReportServiceStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    return;
  }

  std::atomic<bool> listener_ok{false};
  std::thread listener([&]() {
    const bool result = quantara::RunReadOnlyStatusListener(
        g_stop_event, kStatusPipeName, g_safety_state);
    listener_ok.store(result, std::memory_order_relaxed);
    if (!result && g_stop_event != nullptr) {
      SetEvent(g_stop_event);
    }
  });

  ReportServiceStatus(SERVICE_RUNNING);
  WaitForSingleObject(g_stop_event, INFINITE);

  // The listener may be blocked in ConnectNamedPipe or ReadFile. Cancelling
  // synchronous I/O on its owning thread makes SCM stop/shutdown bounded while
  // preserving fail-closed behavior for any partial request.
  CancelSynchronousIo(listener.native_handle());
  listener.join();
  network_monitor.Stop();

  CloseHandle(g_stop_event);
  g_stop_event = nullptr;
  ReportServiceStatus(
      SERVICE_STOPPED,
      listener_ok.load(std::memory_order_relaxed) ? NO_ERROR
                                                  : ERROR_SERVICE_SPECIFIC_ERROR);
}

bool RunCredentialVaultSelfTest() noexcept {
  std::filesystem::path root;
  std::error_code cleanup_error;
  try {
    root = std::filesystem::temp_directory_path() /
           (L"quantara-service-self-test-" +
            std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(root, cleanup_error);

    quantara::CredentialVault vault(root);
    vault.Store(L"self-test", "first-secret");
    const auto first = vault.Load(L"self-test");
    if (!first.has_value() || *first != "first-secret") {
      std::filesystem::remove_all(root, cleanup_error);
      return false;
    }

    vault.Store(L"self-test", "rotated-secret");
    const auto rotated = vault.Load(L"self-test");
    if (!rotated.has_value() || *rotated != "rotated-secret") {
      std::filesystem::remove_all(root, cleanup_error);
      return false;
    }

    vault.Remove(L"self-test");
    const bool removed = !vault.Load(L"self-test").has_value();
    std::filesystem::remove_all(root, cleanup_error);
    return removed;
  } catch (...) {
    if (!root.empty()) {
      std::filesystem::remove_all(root, cleanup_error);
    }
    return false;
  }
}

bool RunLocalPipeSecuritySelfTest() noexcept {
  const std::wstring pipe_name =
      L"\\\\.\\pipe\\QuantaraExecutionService.self-test." +
      std::to_wstring(GetCurrentProcessId());
  HANDLE pipe = quantara::CreateLocalPipeServer(pipe_name);
  if (pipe == INVALID_HANDLE_VALUE) {
    return false;
  }
  const bool unauthenticated_rejected =
      !quantara::AuthenticateConnectedLocalPeer(pipe);
  CloseHandle(pipe);
  return unauthenticated_rejected;
}

bool RunIpcProtocolSelfTest() noexcept {
  try {
    const std::string valid =
        "{\"protocolVersion\":1,\"requestId\":\"status-1\",\"kind\":\"statusRequest\",\"payload\":{}}";
    const std::vector<std::uint8_t> valid_bytes(valid.begin(), valid.end());
    const auto decoded = quantara::DecodeCanonicalReadOnlyRequest(valid_bytes);
    if (!decoded.has_value() || decoded->request_id != "status-1" ||
        decoded->kind != quantara::ReadOnlyRequestKind::kStatusRequest) {
      return false;
    }

    const std::string mutating =
        "{\"protocolVersion\":1,\"requestId\":\"trade-1\",\"kind\":\"executeTrade\",\"payload\":{}}";
    const std::vector<std::uint8_t> mutating_bytes(mutating.begin(),
                                                   mutating.end());
    if (quantara::DecodeCanonicalReadOnlyRequest(mutating_bytes).has_value()) {
      return false;
    }

    const std::string incompatible =
        "{\"protocolVersion\":2,\"requestId\":\"status-2\",\"kind\":\"statusRequest\",\"payload\":{}}";
    const std::vector<std::uint8_t> incompatible_bytes(incompatible.begin(),
                                                       incompatible.end());
    if (quantara::DecodeCanonicalReadOnlyRequest(incompatible_bytes).has_value()) {
      return false;
    }

    quantara::RequestReplayGuard guard(2);
    if (!guard.Accept("request-1") || !guard.Accept("request-2") ||
        guard.Accept("request-1") || !guard.Accept("request-3") ||
        guard.size() != 2 || !guard.Accept("request-1")) {
      return false;
    }
    return guard.size() == 2;
  } catch (...) {
    return false;
  }
}

bool RunAuthenticatedPipeTransportSelfTest() noexcept {
  const std::wstring pipe_name =
      L"\\\\.\\pipe\\QuantaraExecutionService.transport-self-test." +
      std::to_wstring(GetCurrentProcessId());
  HANDLE pipe = quantara::CreateLocalPipeServer(pipe_name);
  if (pipe == INVALID_HANDLE_VALUE) {
    return false;
  }

  HANDLE client_release = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (client_release == nullptr) {
    CloseHandle(pipe);
    return false;
  }

  const std::string payload =
      "{\"protocolVersion\":1,\"requestId\":\"transport-1\",\"kind\":\"statusRequest\",\"payload\":{}}";
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
    const bool write_ok =
        WriteFile(handle, payload.data(), static_cast<DWORD>(payload.size()),
                  &written, nullptr) == TRUE &&
        written == payload.size();
    client_ok.store(write_ok, std::memory_order_relaxed);
    if (write_ok) {
      // Keep the authenticated peer connected until the server has consumed
      // the frame. Closing immediately after WriteFile can race token lookup.
      WaitForSingleObject(client_release, 5000);
    }
    CloseHandle(handle);
  });

  const BOOL connected = ConnectNamedPipe(pipe, nullptr);
  const DWORD connect_error = connected ? ERROR_SUCCESS : GetLastError();
  bool server_ok = connected == TRUE || connect_error == ERROR_PIPE_CONNECTED;
  std::vector<std::uint8_t> message;
  if (server_ok) {
    server_ok = quantara::ReadAuthenticatedLocalMessage(pipe, message);
  }
  if (server_ok) {
    const auto request = quantara::DecodeCanonicalReadOnlyRequest(message);
    quantara::RequestReplayGuard replay_guard;
    server_ok = request.has_value() && request->request_id == "transport-1" &&
                request->kind == quantara::ReadOnlyRequestKind::kStatusRequest &&
                replay_guard.Accept(request->request_id) &&
                !replay_guard.Accept(request->request_id);
  }

  SetEvent(client_release);
  DisconnectNamedPipe(pipe);
  CloseHandle(pipe);
  client.join();
  CloseHandle(client_release);
  return server_ok && client_ok.load(std::memory_order_relaxed);
}

bool RunSelfTest() noexcept {
  g_safety_state.store(quantara::ServiceSafetyState::kDisarmed,
                       std::memory_order_relaxed);
  if (SafetyStateAfterPowerEvent(PBT_APMSUSPEND) !=
      quantara::ServiceSafetyState::kInterrupted) {
    return false;
  }

  g_safety_state.store(quantara::ServiceSafetyState::kInterrupted,
                       std::memory_order_relaxed);
  if (SafetyStateAfterPowerEvent(PBT_APMRESUMEAUTOMATIC) !=
      quantara::ServiceSafetyState::kReconciliationRequired) {
    return false;
  }

  g_safety_state.store(quantara::ServiceSafetyState::kDisarmed,
                       std::memory_order_relaxed);
  if (SafetyStateAfterPowerEvent(0) !=
      quantara::ServiceSafetyState::kDisarmed) {
    return false;
  }

  std::vector<std::uint8_t> rejected_message{0x51};
  if (quantara::ReadAuthenticatedLocalMessage(INVALID_HANDLE_VALUE,
                                              rejected_message) ||
      !rejected_message.empty()) {
    return false;
  }

  return RunCredentialVaultSelfTest() && RunLocalPipeSecuritySelfTest() &&
         RunIpcProtocolSelfTest() && RunAuthenticatedPipeTransportSelfTest();
}
}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc == 2 && std::wstring_view(argv[1]) == L"--self-test") {
    if (!RunSelfTest()) {
      std::wcerr << L"Quantara Windows service self-test failed.\n";
      return 1;
    }
    std::wcout << L"Quantara Windows service self-test passed.\n";
    return 0;
  }

  SERVICE_TABLE_ENTRYW service_table[] = {
      {const_cast<LPWSTR>(kServiceName), ServiceMain},
      {nullptr, nullptr},
  };

  if (!StartServiceCtrlDispatcherW(service_table)) {
    const DWORD error = GetLastError();
    std::wcerr << L"Quantara Windows service dispatcher failed: " << error
               << L"\n";
    return static_cast<int>(error);
  }
  return 0;
}
