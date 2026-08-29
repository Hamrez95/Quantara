#include <windows.h>
#include <ShlObj.h>

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "bitunix_exchange_truth_reader.h"
#include "credential_readiness.h"
#include "credential_vault.h"
#include "ipc_readonly_listener.h"
#include "ipc_request_protocol.h"
#include "ipc_response_protocol.h"
#include "local_pipe_security.h"
#include "local_pipe_transport.h"
#include "management_only_worker_core.h"
#include "network_change_monitor.h"
#include "recovery_evidence_vault.h"
#include "service_shutdown_guard.h"

namespace {
constexpr wchar_t kServiceName[] = L"QuantaraExecutionService";
constexpr wchar_t kStatusPipeName[] =
    L"\\\\.\\pipe\\QuantaraExecutionService.status";

std::atomic<quantara::ServiceSafetyState> g_safety_state{
    quantara::ServiceSafetyState::kDisarmed};
std::atomic<quantara::CredentialReadiness> g_credential_readiness{
    quantara::CredentialReadiness::kInvalid};
SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status{};
HANDLE g_stop_event = nullptr;
HANDLE g_network_reconciliation_event = nullptr;
HANDLE g_power_reconciliation_event = nullptr;

std::optional<std::filesystem::path> ProgramDataCredentialRoot() noexcept {
  PWSTR raw_path = nullptr;
  const HRESULT result =
      SHGetKnownFolderPath(FOLDERID_ProgramData, KF_FLAG_DEFAULT, nullptr,
                           &raw_path);
  if (FAILED(result) || raw_path == nullptr) {
    if (raw_path != nullptr) {
      CoTaskMemFree(raw_path);
    }
    return std::nullopt;
  }

  std::filesystem::path root(raw_path);
  CoTaskMemFree(raw_path);
  return root / L"Quantara" / L"ServiceCredentials";
}

quantara::ServiceSafetyState SafetyStateForCredentialReadiness(
    quantara::CredentialReadiness readiness) noexcept {
  return quantara::CredentialReadinessRequiresReconciliation(readiness)
             ? quantara::ServiceSafetyState::kReconciliationRequired
             : quantara::ServiceSafetyState::kDisarmed;
}

quantara::CredentialReadiness CredentialStartupReadiness() noexcept {
  const auto root = ProgramDataCredentialRoot();
  if (!root.has_value()) {
    return quantara::CredentialReadiness::kInvalid;
  }
  return quantara::EvaluateCredentialReadiness(*root);
}

quantara::ServiceSafetyState ReconcileManagementOnly(
    quantara::CredentialReadiness readiness,
    quantara::RecoveryLifecycleBoundary boundary) noexcept {
  if (readiness != quantara::CredentialReadiness::kReady) {
    return SafetyStateForCredentialReadiness(readiness);
  }

  const auto root = ProgramDataCredentialRoot();
  if (!root.has_value()) {
    return quantara::ServiceSafetyState::kReconciliationRequired;
  }

  quantara::WindowsManagementOnlyWorkerCore worker;
  worker.MarkLifecycleBoundary(boundary);

  const auto positions_auth = quantara::GenerateBitunixReadOnlyAuthStamp();
  const auto orders_auth = quantara::GenerateBitunixReadOnlyAuthStamp();
  if (!positions_auth.has_value() || !orders_auth.has_value()) {
    return quantara::ServiceSafetyState::kReconciliationRequired;
  }

  const auto truth = quantara::ReadBitunixExchangeTruth(
      *root, *positions_auth, *orders_auth);
  if (!truth.has_value()) {
    return quantara::ServiceSafetyState::kReconciliationRequired;
  }

  // Durable ownership is consumed only from the service-owned protected vault.
  // Missing storage is a valid empty snapshot (so exchange positions remain
  // external/unmanaged); corrupt, tampered or unsupported payloads fail closed.
  quantara::RecoveryEvidenceVault evidence_vault(*root);
  const auto durable_evidence = evidence_vault.Load();
  if (!durable_evidence.has_value()) {
    return quantara::ServiceSafetyState::kReconciliationRequired;
  }

  const auto snapshot =
      worker.ReconcileFreshExchangeTruth(*truth, *durable_evidence);
  if (!snapshot.has_value() || worker.CanOpenNewEntry()) {
    return quantara::ServiceSafetyState::kReconciliationRequired;
  }
  return quantara::ServiceSafetyStateFromManagementOnlySnapshot(*snapshot);
}

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
      // Stop/shutdown is an immediate authority boundary. Publish a distinct
      // fail-closed state before signaling the worker so an in-flight
      // reconciliation cannot successfully CAS management authority afterward.
      g_safety_state.store(quantara::ServiceSafetyStateForStopBoundary(),
                           std::memory_order_seq_cst);
      ReportServiceStatus(SERVICE_STOP_PENDING, NO_ERROR, 5000);
      if (g_stop_event != nullptr) {
        SetEvent(g_stop_event);
      }
      return NO_ERROR;
    case SERVICE_CONTROL_POWEREVENT: {
      const auto next = SafetyStateAfterPowerEvent(event_type);
      g_safety_state.store(next, std::memory_order_relaxed);
      if (next == quantara::ServiceSafetyState::kReconciliationRequired &&
          g_power_reconciliation_event != nullptr) {
        SetEvent(g_power_reconciliation_event);
      }
      return NO_ERROR;
    }
    default:
      return NO_ERROR;
  }
}

void CloseLifecycleEvents() noexcept {
  if (g_network_reconciliation_event != nullptr) {
    CloseHandle(g_network_reconciliation_event);
    g_network_reconciliation_event = nullptr;
  }
  if (g_power_reconciliation_event != nullptr) {
    CloseHandle(g_power_reconciliation_event);
    g_power_reconciliation_event = nullptr;
  }
}

void WINAPI ServiceMain(DWORD /*argc*/, LPWSTR* /*argv*/) noexcept {
  g_status_handle =
      RegisterServiceCtrlHandlerExW(kServiceName, ServiceControlHandler, nullptr);
  if (g_status_handle == nullptr) {
    return;
  }

  ReportServiceStatus(SERVICE_START_PENDING, NO_ERROR, 35000);
  g_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_stop_event == nullptr) {
    ReportServiceStatus(SERVICE_STOPPED, GetLastError());
    return;
  }
  g_network_reconciliation_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_power_reconciliation_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_network_reconciliation_event == nullptr ||
      g_power_reconciliation_event == nullptr) {
    const DWORD error = GetLastError();
    CloseLifecycleEvents();
    CloseHandle(g_stop_event);
    g_stop_event = nullptr;
    ReportServiceStatus(SERVICE_STOPPED, error);
    return;
  }

  HANDLE listener_ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (listener_ready == nullptr) {
    const DWORD error = GetLastError();
    CloseLifecycleEvents();
    CloseHandle(g_stop_event);
    g_stop_event = nullptr;
    ReportServiceStatus(SERVICE_STOPPED, error);
    return;
  }

  const auto credential_readiness = CredentialStartupReadiness();
  g_credential_readiness.store(credential_readiness,
                               std::memory_order_relaxed);
  g_safety_state.store(
      ReconcileManagementOnly(credential_readiness,
                              quantara::RecoveryLifecycleBoundary::kRestart),
      std::memory_order_relaxed);

  quantara::NetworkChangeMonitor network_monitor(
      g_safety_state, g_network_reconciliation_event);
  if (!network_monitor.Start()) {
    CloseHandle(listener_ready);
    CloseLifecycleEvents();
    CloseHandle(g_stop_event);
    g_stop_event = nullptr;
    ReportServiceStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    return;
  }

  std::atomic<bool> listener_ok{false};
  std::thread listener([&]() {
    const bool result = quantara::RunReadOnlyStatusListener(
        g_stop_event, kStatusPipeName, g_safety_state, g_credential_readiness,
        listener_ready);
    listener_ok.store(result, std::memory_order_relaxed);
    if (!result && g_stop_event != nullptr) {
      SetEvent(g_stop_event);
    }
  });

  const DWORD readiness = WaitForSingleObject(listener_ready, 5000);
  if (readiness != WAIT_OBJECT_0) {
    SetEvent(g_stop_event);
    CancelSynchronousIo(listener.native_handle());
    listener.join();
    network_monitor.Stop();
    CloseHandle(listener_ready);
    CloseLifecycleEvents();
    CloseHandle(g_stop_event);
    g_stop_event = nullptr;
    ReportServiceStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    return;
  }
  CloseHandle(listener_ready);

  ReportServiceStatus(SERVICE_RUNNING);

  const HANDLE service_events[] = {
      g_stop_event,
      g_network_reconciliation_event,
      g_power_reconciliation_event,
  };
  bool stopping = false;
  while (!stopping) {
    const DWORD signaled = WaitForMultipleObjects(3, service_events, FALSE,
                                                  INFINITE);
    if (signaled == WAIT_OBJECT_0) {
      stopping = true;
      continue;
    }
    if (signaled != WAIT_OBJECT_0 + 1 && signaled != WAIT_OBJECT_0 + 2) {
      g_safety_state.store(
          quantara::ServiceSafetyState::kReconciliationRequired,
          std::memory_order_relaxed);
      stopping = true;
      continue;
    }

    HANDLE boundary_event =
        signaled == WAIT_OBJECT_0 + 1 ? g_network_reconciliation_event
                                      : g_power_reconciliation_event;
    const auto boundary =
        signaled == WAIT_OBJECT_0 + 1
            ? quantara::RecoveryLifecycleBoundary::kNetworkRestored
            : quantara::RecoveryLifecycleBoundary::kPowerResume;

    ResetEvent(boundary_event);
    g_safety_state.store(quantara::ServiceSafetyState::kReconciliationRequired,
                         std::memory_order_relaxed);
    const auto refreshed_readiness = CredentialStartupReadiness();
    g_credential_readiness.store(refreshed_readiness,
                                 std::memory_order_relaxed);
    const auto reconciled =
        ReconcileManagementOnly(refreshed_readiness, boundary);

    const bool stop_requested =
        WaitForSingleObject(g_stop_event, 0) == WAIT_OBJECT_0;
    const bool newer_boundary_arrived =
        WaitForSingleObject(g_network_reconciliation_event, 0) ==
            WAIT_OBJECT_0 ||
        WaitForSingleObject(g_power_reconciliation_event, 0) == WAIT_OBJECT_0;
    if (!quantara::ShouldPublishReconciliationResult(
            stop_requested, newer_boundary_arrived)) {
      if (stop_requested) {
        g_safety_state.store(quantara::ServiceSafetyStateForStopBoundary(),
                             std::memory_order_seq_cst);
        stopping = true;
      } else {
        g_safety_state.store(
            quantara::ServiceSafetyState::kReconciliationRequired,
            std::memory_order_relaxed);
      }
      continue;
    }

    // Publish only while the state still reflects this reconciliation cycle.
    // STOP/SHUTDOWN writes kInterrupted first, so a stop that races between the
    // zero-time event check above and this CAS makes publication fail. If this
    // CAS wins first, the control handler runs afterward and immediately
    // overwrites the result with kInterrupted. Either ordering ends fail-closed.
    auto expected = quantara::ServiceSafetyState::kReconciliationRequired;
    if (!g_safety_state.compare_exchange_strong(
            expected, reconciled, std::memory_order_seq_cst,
            std::memory_order_seq_cst)) {
      if (expected == quantara::ServiceSafetyStateForStopBoundary()) {
        stopping = true;
      }
      continue;
    }
  }

  CancelSynchronousIo(listener.native_handle());
  listener.join();
  network_monitor.Stop();

  CloseLifecycleEvents();
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

    const std::string credential_status =
        "{\"protocolVersion\":1,\"requestId\":\"credential-1\",\"kind\":\"credentialReadinessRequest\",\"payload\":{}}";
    const std::vector<std::uint8_t> credential_status_bytes(
        credential_status.begin(), credential_status.end());
    const auto credential_decoded =
        quantara::DecodeCanonicalReadOnlyRequest(credential_status_bytes);
    if (!credential_decoded.has_value() ||
        credential_decoded->request_id != "credential-1" ||
        credential_decoded->kind !=
            quantara::ReadOnlyRequestKind::kCredentialReadinessRequest) {
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

bool RunManagementOnlyRuntimeSelfTest() noexcept {
  quantara::WindowsManagementOnlyWorkerCore worker;
  worker.MarkLifecycleBoundary(quantara::RecoveryLifecycleBoundary::kRestart);

  quantara::BitunixExchangeTruthSnapshot empty_truth{};
  empty_truth.pending_orders.total = 0;
  const auto empty_snapshot =
      worker.ReconcileFreshExchangeTruth(empty_truth, {});
  if (!empty_snapshot.has_value() || worker.CanOpenNewEntry() ||
      quantara::ServiceSafetyStateFromManagementOnlySnapshot(*empty_snapshot) !=
          quantara::ServiceSafetyState::kDisarmed) {
    return false;
  }

  quantara::BitunixExchangeTruthSnapshot external_truth{};
  external_truth.positions.push_back({"manual-position-1", "BTCUSDT", "LONG",
                                      "ISOLATION", "HEDGE", "0.01", 2});
  external_truth.pending_orders.total = 0;
  const auto external_snapshot =
      worker.ReconcileFreshExchangeTruth(external_truth, {});
  return external_snapshot.has_value() &&
         external_snapshot->classification ==
             quantara::ExistingPositionClassification::kExternalUnmanaged &&
         !worker.CanManageExistingPositions() && !worker.CanOpenNewEntry() &&
         quantara::ServiceSafetyStateFromManagementOnlySnapshot(
             *external_snapshot) == quantara::ServiceSafetyState::kDisarmed;
}

bool RunLifecycleReconciliationEventSelfTest() noexcept {
  HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (event == nullptr) {
    return false;
  }
  if (WaitForSingleObject(event, 0) != WAIT_TIMEOUT || !SetEvent(event) ||
      WaitForSingleObject(event, 0) != WAIT_OBJECT_0 || !ResetEvent(event) ||
      WaitForSingleObject(event, 0) != WAIT_TIMEOUT) {
    CloseHandle(event);
    return false;
  }
  CloseHandle(event);
  return true;
}

bool RunSelfTest() noexcept {
  if (SafetyStateForCredentialReadiness(quantara::CredentialReadiness::kMissing) !=
          quantara::ServiceSafetyState::kDisarmed ||
      SafetyStateForCredentialReadiness(quantara::CredentialReadiness::kReady) !=
          quantara::ServiceSafetyState::kDisarmed ||
      SafetyStateForCredentialReadiness(
          quantara::CredentialReadiness::kIncomplete) !=
          quantara::ServiceSafetyState::kReconciliationRequired ||
      SafetyStateForCredentialReadiness(quantara::CredentialReadiness::kInvalid) !=
          quantara::ServiceSafetyState::kReconciliationRequired) {
    return false;
  }

  if (quantara::ServiceSafetyStateForStopBoundary() !=
          quantara::ServiceSafetyState::kInterrupted ||
      quantara::ShouldPublishReconciliationResult(true, false) ||
      quantara::ShouldPublishReconciliationResult(false, true) ||
      !quantara::ShouldPublishReconciliationResult(false, false)) {
    return false;
  }

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
         RunIpcProtocolSelfTest() && RunAuthenticatedPipeTransportSelfTest() &&
         RunManagementOnlyRuntimeSelfTest() &&
         RunLifecycleReconciliationEventSelfTest();
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