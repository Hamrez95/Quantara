#include <windows.h>

#include <atomic>
#include <filesystem>
#include <iostream>
#include <string_view>

#include "credential_vault.h"

namespace {
constexpr wchar_t kServiceName[] = L"QuantaraExecutionService";

enum class RuntimeSafetyState {
  kDisarmed,
  kInterrupted,
  kReconciliationRequired,
};

std::atomic<RuntimeSafetyState> g_safety_state{RuntimeSafetyState::kDisarmed};
SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status{};
HANDLE g_stop_event = nullptr;

RuntimeSafetyState SafetyStateAfterPowerEvent(DWORD event_type) noexcept {
  switch (event_type) {
    case PBT_APMSUSPEND:
      return RuntimeSafetyState::kInterrupted;
    case PBT_APMRESUMEAUTOMATIC:
    case PBT_APMRESUMECRITICAL:
    case PBT_APMRESUMESUSPEND:
      return RuntimeSafetyState::kReconciliationRequired;
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

  // A service start never grants execution authority. The future authenticated
  // IPC/reconciliation layer must explicitly transition out of this state.
  g_safety_state.store(RuntimeSafetyState::kDisarmed,
                       std::memory_order_relaxed);
  ReportServiceStatus(SERVICE_RUNNING);

  WaitForSingleObject(g_stop_event, INFINITE);
  CloseHandle(g_stop_event);
  g_stop_event = nullptr;
  ReportServiceStatus(SERVICE_STOPPED);
}

bool RunCredentialVaultSelfTest() noexcept {
  const auto root = std::filesystem::temp_directory_path() /
                    (L"quantara-service-self-test-" +
                     std::to_wstring(GetCurrentProcessId()));
  std::error_code cleanup_error;
  std::filesystem::remove_all(root, cleanup_error);

  try {
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
    std::filesystem::remove_all(root, cleanup_error);
    return false;
  }
}

bool RunSelfTest() noexcept {
  g_safety_state.store(RuntimeSafetyState::kDisarmed,
                       std::memory_order_relaxed);
  if (SafetyStateAfterPowerEvent(PBT_APMSUSPEND) !=
      RuntimeSafetyState::kInterrupted) {
    return false;
  }

  g_safety_state.store(RuntimeSafetyState::kInterrupted,
                       std::memory_order_relaxed);
  if (SafetyStateAfterPowerEvent(PBT_APMRESUMEAUTOMATIC) !=
      RuntimeSafetyState::kReconciliationRequired) {
    return false;
  }

  g_safety_state.store(RuntimeSafetyState::kDisarmed,
                       std::memory_order_relaxed);
  if (SafetyStateAfterPowerEvent(0) != RuntimeSafetyState::kDisarmed) {
    return false;
  }

  return RunCredentialVaultSelfTest();
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
