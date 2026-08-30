#include <windows.h>
#include <shellapi.h>

#include <array>
#include <cwchar>
#include <filesystem>
#include <iostream>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#pragma comment(lib, "advapi32.lib")

namespace {

constexpr wchar_t kWindowClassName[] = L"QuantaraTrayStatusMonitor";
constexpr wchar_t kWindowTitle[] = L"Quantara status monitor";
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\QuantaraWindowsTrayStatusMonitor";
constexpr wchar_t kExecutionServiceName[] = L"QuantaraExecutionService";
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT_PTR kRefreshTimerId = 1;
constexpr UINT kRefreshIntervalMs = 5000;
constexpr DWORD kStatusClientTimeoutMs = 3500;
constexpr DWORD kServiceTransitionTimeoutMs = 20000;
constexpr DWORD kMaxStatusBytes = 64 * 1024;
constexpr UINT kOpenCommand = 1001;
constexpr UINT kStatusCommand = 1002;
constexpr UINT kRestartServiceCommand = 1003;
constexpr UINT kExitCommand = 1004;

UINT g_taskbar_created_message = 0;

class ScopedHandle final {
 public:
  explicit ScopedHandle(HANDLE handle = nullptr) noexcept : handle_(handle) {}
  ~ScopedHandle() {
    if (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE) {
      CloseHandle(handle_);
    }
  }
  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  HANDLE get() const noexcept { return handle_; }
  HANDLE release() noexcept {
    HANDLE value = handle_;
    handle_ = nullptr;
    return value;
  }

 private:
  HANDLE handle_;
};

class ScopedServiceHandle final {
 public:
  explicit ScopedServiceHandle(SC_HANDLE handle = nullptr) noexcept
      : handle_(handle) {}
  ~ScopedServiceHandle() {
    if (handle_ != nullptr) {
      CloseServiceHandle(handle_);
    }
  }
  ScopedServiceHandle(const ScopedServiceHandle&) = delete;
  ScopedServiceHandle& operator=(const ScopedServiceHandle&) = delete;

  SC_HANDLE get() const noexcept { return handle_; }

 private:
  SC_HANDLE handle_;
};

enum class ServiceTrayState {
  unavailable,
  disarmed,
  interrupted,
  reconciliation_required,
  manage_existing_only,
};

std::filesystem::path ExecutableDirectory() {
  std::array<wchar_t, 32768> buffer{};
  const DWORD length =
      GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (length == 0 || length >= static_cast<DWORD>(buffer.size())) {
    return {};
  }
  return std::filesystem::path(std::wstring(buffer.data(), length)).parent_path();
}

std::filesystem::path StatusClientPath() {
  return ExecutableDirectory() / L"quantara_windows_service_client.exe";
}

std::filesystem::path AppExecutablePath() {
  return ExecutableDirectory().parent_path() / L"quantara_app.exe";
}

ServiceTrayState ParseCanonicalStatus(std::string_view response) noexcept {
  while (!response.empty() &&
         (response.back() == '\r' || response.back() == '\n')) {
    response.remove_suffix(1);
  }

  constexpr std::string_view kPrefix =
      "{\"protocolVersion\":1,\"requestId\":\"";
  constexpr std::string_view kKind =
      "\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"";
  constexpr std::string_view kSuffix = "\",\"entryAuthority\":false}}";

  if (!response.starts_with(kPrefix) || !response.ends_with(kSuffix)) {
    return ServiceTrayState::unavailable;
  }
  const auto kind_position = response.find(kKind, kPrefix.size());
  if (kind_position == std::string_view::npos) {
    return ServiceTrayState::unavailable;
  }
  const auto state_start = kind_position + kKind.size();
  if (state_start + kSuffix.size() > response.size()) {
    return ServiceTrayState::unavailable;
  }
  const auto state_size = response.size() - state_start - kSuffix.size();
  const auto state = response.substr(state_start, state_size);
  if (state == "disarmed") {
    return ServiceTrayState::disarmed;
  }
  if (state == "interrupted") {
    return ServiceTrayState::interrupted;
  }
  if (state == "reconciliationRequired") {
    return ServiceTrayState::reconciliation_required;
  }
  if (state == "manageExistingOnly") {
    return ServiceTrayState::manage_existing_only;
  }
  return ServiceTrayState::unavailable;
}

std::wstring StateLabel(ServiceTrayState state) {
  switch (state) {
    case ServiceTrayState::disarmed:
      return L"Disarmed";
    case ServiceTrayState::interrupted:
      return L"Interrupted - entries blocked";
    case ServiceTrayState::reconciliation_required:
      return L"Reconciliation required - entries blocked";
    case ServiceTrayState::manage_existing_only:
      return L"Managing verified existing positions - entries blocked";
    case ServiceTrayState::unavailable:
    default:
      return L"Status unavailable - entries unverified";
  }
}

bool ReadChildOutput(const std::filesystem::path& client_path,
                     std::string& output) noexcept {
  output.clear();
  try {
    if (client_path.empty() || !std::filesystem::is_regular_file(client_path)) {
      return false;
    }

    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.bInheritHandle = TRUE;

    HANDLE raw_read = nullptr;
    HANDLE raw_write = nullptr;
    if (!CreatePipe(&raw_read, &raw_write, &attributes, 0)) {
      return false;
    }
    ScopedHandle read_pipe(raw_read);
    ScopedHandle write_pipe(raw_write);
    if (!SetHandleInformation(read_pipe.get(), HANDLE_FLAG_INHERIT, 0)) {
      return false;
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdOutput = write_pipe.get();
    startup.hStdError = write_pipe.get();
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    PROCESS_INFORMATION process_info{};
    std::wstring command_line = L"\"" + client_path.wstring() + L"\" --status";
    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');

    if (!CreateProcessW(client_path.c_str(), mutable_command.data(), nullptr,
                        nullptr, TRUE, CREATE_NO_WINDOW, nullptr,
                        client_path.parent_path().c_str(), &startup,
                        &process_info)) {
      return false;
    }
    ScopedHandle process(process_info.hProcess);
    ScopedHandle thread(process_info.hThread);
    const HANDLE inherited_write = write_pipe.release();
    if (inherited_write != nullptr && inherited_write != INVALID_HANDLE_VALUE) {
      CloseHandle(inherited_write);
    }

    const DWORD wait = WaitForSingleObject(process.get(), kStatusClientTimeoutMs);
    if (wait != WAIT_OBJECT_0) {
      TerminateProcess(process.get(), ERROR_TIMEOUT);
      WaitForSingleObject(process.get(), 1000);
      return false;
    }

    DWORD exit_code = ERROR_GEN_FAILURE;
    if (!GetExitCodeProcess(process.get(), &exit_code) || exit_code != 0) {
      return false;
    }

    std::array<char, 4096> buffer{};
    for (;;) {
      DWORD bytes_read = 0;
      if (!ReadFile(read_pipe.get(), buffer.data(),
                    static_cast<DWORD>(buffer.size()), &bytes_read, nullptr)) {
        const DWORD error = GetLastError();
        if (error == ERROR_BROKEN_PIPE) {
          break;
        }
        return false;
      }
      if (bytes_read == 0) {
        break;
      }
      if (output.size() + bytes_read > kMaxStatusBytes) {
        output.clear();
        return false;
      }
      output.append(buffer.data(), bytes_read);
    }
    return !output.empty();
  } catch (...) {
    output.clear();
    return false;
  }
}

ServiceTrayState QueryServiceState() noexcept {
  std::string output;
  if (!ReadChildOutput(StatusClientPath(), output)) {
    return ServiceTrayState::unavailable;
  }
  return ParseCanonicalStatus(output);
}

bool QueryNativeServiceState(SC_HANDLE service, DWORD& state) noexcept {
  SERVICE_STATUS_PROCESS status{};
  DWORD bytes_needed = 0;
  if (!QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO,
                            reinterpret_cast<LPBYTE>(&status), sizeof(status),
                            &bytes_needed)) {
    return false;
  }
  state = status.dwCurrentState;
  return true;
}

bool WaitForNativeServiceState(SC_HANDLE service, DWORD desired_state,
                               DWORD timeout_ms) noexcept {
  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  for (;;) {
    DWORD current_state = 0;
    if (!QueryNativeServiceState(service, current_state)) {
      return false;
    }
    if (current_state == desired_state) {
      return true;
    }
    if (GetTickCount64() >= deadline) {
      return false;
    }
    Sleep(100);
  }
}

bool RestartExecutionService() noexcept {
  ScopedServiceHandle manager(
      OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT));
  if (manager.get() == nullptr) {
    return false;
  }

  ScopedServiceHandle service(OpenServiceW(
      manager.get(), kExecutionServiceName,
      SERVICE_QUERY_STATUS | SERVICE_STOP | SERVICE_START));
  if (service.get() == nullptr) {
    return false;
  }

  DWORD state = 0;
  if (!QueryNativeServiceState(service.get(), state)) {
    return false;
  }

  if (state != SERVICE_STOPPED) {
    if (state == SERVICE_STOP_PENDING) {
      if (!WaitForNativeServiceState(service.get(), SERVICE_STOPPED,
                                     kServiceTransitionTimeoutMs)) {
        return false;
      }
    } else {
      if (state == SERVICE_START_PENDING &&
          !WaitForNativeServiceState(service.get(), SERVICE_RUNNING,
                                     kServiceTransitionTimeoutMs)) {
        return false;
      }
      SERVICE_STATUS status{};
      if (!ControlService(service.get(), SERVICE_CONTROL_STOP, &status) &&
          GetLastError() != ERROR_SERVICE_NOT_ACTIVE) {
        return false;
      }
      if (!WaitForNativeServiceState(service.get(), SERVICE_STOPPED,
                                     kServiceTransitionTimeoutMs)) {
        return false;
      }
    }
  }

  if (!StartServiceW(service.get(), 0, nullptr) &&
      GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) {
    return false;
  }
  return WaitForNativeServiceState(service.get(), SERVICE_RUNNING,
                                   kServiceTransitionTimeoutMs);
}

bool CopyTooltip(NOTIFYICONDATAW& data, std::wstring_view tooltip) noexcept {
  if (tooltip.size() >= std::size(data.szTip)) {
    return false;
  }
  const errno_t result = wcsncpy_s(data.szTip, std::size(data.szTip),
                                   tooltip.data(), tooltip.size());
  return result == 0;
}

NOTIFYICONDATAW BuildTrayData(HWND window, ServiceTrayState state) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = 1;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  const std::wstring tooltip = L"Quantara - " + StateLabel(state);
  if (!CopyTooltip(data, tooltip)) {
    CopyTooltip(data, L"Quantara - status unavailable");
  }
  return data;
}

bool AddTrayIcon(HWND window, ServiceTrayState state) noexcept {
  auto data = BuildTrayData(window, state);
  if (!Shell_NotifyIconW(NIM_ADD, &data)) {
    return false;
  }
  data.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &data);
  return true;
}

void UpdateTray(HWND window, ServiceTrayState state) {
  auto data = BuildTrayData(window, state);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void OpenQuantara() noexcept {
  try {
    const auto app_path = AppExecutablePath();
    if (app_path.empty() || !std::filesystem::is_regular_file(app_path)) {
      return;
    }
    ShellExecuteW(nullptr, L"open", app_path.c_str(), nullptr,
                  app_path.parent_path().c_str(), SW_SHOWNORMAL);
  } catch (...) {
  }
}

void ShowTrayMenu(HWND window, ServiceTrayState state) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  const std::wstring status = L"Status: " + StateLabel(state);
  AppendMenuW(menu, MF_STRING, kOpenCommand, L"Open Quantara");
  AppendMenuW(menu, MF_STRING | MF_DISABLED | MF_GRAYED, kStatusCommand,
              status.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kRestartServiceCommand,
              L"Restart execution service (fail-closed)");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kExitCommand, L"Exit status monitor");

  POINT point{};
  if (GetCursorPos(&point)) {
    SetForegroundWindow(window);
    TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
                   point.x, point.y, 0, window, nullptr);
  }
  DestroyMenu(menu);
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
  static ServiceTrayState state = ServiceTrayState::unavailable;
  if (g_taskbar_created_message != 0 && message == g_taskbar_created_message) {
    AddTrayIcon(window, state);
    return 0;
  }

  switch (message) {
    case WM_CREATE: {
      state = QueryServiceState();
      if (!AddTrayIcon(window, state)) {
        return -1;
      }
      if (SetTimer(window, kRefreshTimerId, kRefreshIntervalMs, nullptr) == 0) {
        auto data = BuildTrayData(window, state);
        Shell_NotifyIconW(NIM_DELETE, &data);
        return -1;
      }
      return 0;
    }
    case WM_TIMER:
      if (wparam == kRefreshTimerId) {
        state = QueryServiceState();
        UpdateTray(window, state);
      }
      return 0;
    case kTrayMessage:
      if (LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        OpenQuantara();
      } else if (LOWORD(lparam) == WM_RBUTTONUP ||
                 LOWORD(lparam) == WM_CONTEXTMENU) {
        ShowTrayMenu(window, state);
      }
      return 0;
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kOpenCommand:
          OpenQuantara();
          return 0;
        case kRestartServiceCommand: {
          const int confirmation = MessageBoxW(
              window,
              L"Restart the Quantara execution service?\n\nThe service will "
              L"start fail-closed. Restarting never restores entry authority; "
              L"fresh reconciliation is required before any future entry "
              L"authority can be considered.",
              L"Restart Quantara execution service",
              MB_OKCANCEL | MB_ICONWARNING | MB_DEFBUTTON2);
          if (confirmation != IDOK) {
            return 0;
          }
          const bool restarted = RestartExecutionService();
          state = QueryServiceState();
          UpdateTray(window, state);
          MessageBoxW(
              window,
              restarted
                  ? L"The execution service restarted. Quantara remains "
                    L"fail-closed until fresh reconciliation establishes a "
                    L"safe state."
                  : L"The execution service could not be restarted. No "
                    L"authority was restored. Check service permissions and "
                    L"status before taking further action.",
              restarted ? L"Quantara service restarted"
                        : L"Quantara service restart failed",
              MB_OK | (restarted ? MB_ICONINFORMATION : MB_ICONERROR));
          return 0;
        }
        case kExitCommand:
          DestroyWindow(window);
          return 0;
        default:
          return 0;
      }
    case WM_DESTROY: {
      KillTimer(window, kRefreshTimerId);
      auto data = BuildTrayData(window, state);
      Shell_NotifyIconW(NIM_DELETE, &data);
      PostQuitMessage(0);
      return 0;
    }
    default:
      return DefWindowProcW(window, message, wparam, lparam);
  }
}

int RunSelfTest() {
  const std::string disarmed =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.1\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"disarmed\",\"entryAuthority\":false}}\n";
  const std::string interrupted =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.2\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"interrupted\",\"entryAuthority\":false}}";
  const std::string reconciliation =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.3\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"reconciliationRequired\",\"entryAuthority\":false}}";
  const std::string management_only =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.4\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"manageExistingOnly\",\"entryAuthority\":false}}";
  const std::string unsafe =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.5\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"manageExistingOnly\",\"entryAuthority\":true}}";

  if (ParseCanonicalStatus(disarmed) != ServiceTrayState::disarmed ||
      ParseCanonicalStatus(interrupted) != ServiceTrayState::interrupted ||
      ParseCanonicalStatus(reconciliation) !=
          ServiceTrayState::reconciliation_required ||
      ParseCanonicalStatus(management_only) !=
          ServiceTrayState::manage_existing_only ||
      ParseCanonicalStatus(unsafe) != ServiceTrayState::unavailable ||
      ParseCanonicalStatus("not-json") != ServiceTrayState::unavailable ||
      StateLabel(ServiceTrayState::manage_existing_only).empty() ||
      StateLabel(ServiceTrayState::unavailable).empty()) {
    std::cerr << "Windows tray status monitor self-test failed.\n";
    return 1;
  }
  return 0;
}

int RunTrayMonitor(HINSTANCE instance) {
  SetLastError(ERROR_SUCCESS);
  ScopedHandle single_instance(
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName));
  if (single_instance.get() == nullptr) {
    return 4;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    return 0;
  }

  g_taskbar_created_message = RegisterWindowMessageW(L"TaskbarCreated");
  if (g_taskbar_created_message == 0) {
    return 5;
  }

  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = WindowProcedure;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClassName;
  window_class.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  if (RegisterClassExW(&window_class) == 0) {
    return 2;
  }

  HWND window = CreateWindowExW(0, kWindowClassName, kWindowTitle, 0, 0, 0, 0,
                                0, nullptr, nullptr, instance, nullptr);
  if (window == nullptr) {
    UnregisterClassW(kWindowClassName, instance);
    return 3;
  }

  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  UnregisterClassW(kWindowClassName, instance);
  return 0;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR command_line, int) {
  if (command_line != nullptr &&
      std::wstring_view(command_line) == L"--self-test") {
    return RunSelfTest();
  }
  return RunTrayMonitor(instance);
}
