#include <windows.h>

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <string_view>
#include <thread>
#include <vector>

#include "credential_vault.h"
#include "local_pipe_security.h"
#include "local_pipe_transport.h"

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

bool RunAuthenticatedPipeTransportSelfTest() noexcept {
  const std::wstring pipe_name =
      L"\\\\.\\pipe\\QuantaraExecutionService.transport-self-test." +
      std::to_wstring(GetCurrentProcessId());
  HANDLE pipe = quantara::CreateLocalPipeServer(pipe_name);
  if (pipe == INVALID_HANDLE_VALUE) {
    return false;
  }

  constexpr std::uint8_t kPayload[] = {0x51, 0x54, 0x52, 0x41};
  std::atomic<bool> client_ok{false};
  std::thread client([&]() {
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
    client_ok.store(WriteFile(handle, kPayload, sizeof(kPayload), &written,
                              nullptr) == TRUE &&
                        written == sizeof(kPayload),
                    std::memory_order_relaxed);
    CloseHandle(handle);
  });

  const BOOL connected = ConnectNamedPipe(pipe, nullptr);
  const DWORD connect_error = connected ? ERROR_SUCCESS : GetLastError();
  bool server_ok = connected == TRUE || connect_error == ERROR_PIPE_CONNECTED;
  std::vector<std::uint8_t> message;
  if (server_ok) {
    server_ok = quantara::ReadAuthenticatedLocalMessage(pipe, message) &&
                message.size() == sizeof(kPayload);
    for (size_t index = 0; server_ok && index < message.size(); ++index) {
      server_ok = message[index] == kPayload[index];
    }
  }

  DisconnectNamedPipe(pipe);
  CloseHandle(pipe);
  client.join();
  return server_ok && client_ok.load(std::memory_order_relaxed);
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

  return RunCredentialVaultSelfTest() && RunLocalPipeSecuritySelfTest() &&
         RunAuthenticatedPipeTransportSelfTest();
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
