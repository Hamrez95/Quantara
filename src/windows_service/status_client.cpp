#include <windows.h>
#include <winsvc.h>

#include <charconv>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr wchar_t kServiceName[] = L"QuantaraExecutionService";
constexpr wchar_t kStatusPipeName[] =
    L"\\\\.\\pipe\\QuantaraExecutionService.status";
constexpr DWORD kMaxFrameBytes = 64 * 1024;
constexpr DWORD kIoTimeoutMs = 3000;

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

std::string BuildRequestId() {
  return "client." + std::to_string(GetCurrentProcessId()) + "." +
         std::to_string(GetTickCount64());
}

std::string BuildStatusRequest(std::string_view request_id) {
  return "{\"protocolVersion\":1,\"requestId\":\"" +
         std::string(request_id) +
         "\",\"kind\":\"statusRequest\",\"payload\":{}}";
}

std::string BuildCredentialReadinessRequest(std::string_view request_id) {
  return "{\"protocolVersion\":1,\"requestId\":\"" +
         std::string(request_id) +
         "\",\"kind\":\"credentialReadinessRequest\",\"payload\":{}}";
}

bool IsCanonicalPositionId(std::wstring_view position_id) noexcept {
  if (position_id.empty() || position_id.size() > 64 || position_id == L"0") {
    return false;
  }
  for (const wchar_t ch : position_id) {
    if (ch < L'0' || ch > L'9') {
      return false;
    }
  }
  return true;
}

std::string NarrowPositionId(std::wstring_view position_id) {
  std::string result;
  result.reserve(position_id.size());
  for (const wchar_t ch : position_id) {
    result.push_back(static_cast<char>(ch));
  }
  return result;
}

std::optional<std::string> CanonicalPositiveFinitePrice(
    std::wstring_view price) noexcept {
  if (price.empty() || price.size() > 64) return std::nullopt;
  std::string value;
  value.reserve(price.size());
  for (const wchar_t ch : price) {
    if (ch < 0x21 || ch > 0x7e) return std::nullopt;
    value.push_back(static_cast<char>(ch));
  }
  double parsed = 0.0;
  const auto result =
      std::from_chars(value.data(), value.data() + value.size(), parsed);
  if (result.ec != std::errc{} || result.ptr != value.data() + value.size() ||
      !std::isfinite(parsed) || parsed <= 0.0) {
    return std::nullopt;
  }
  return value;
}

std::string BuildCloseExistingPositionRequest(std::string_view request_id,
                                              std::string_view position_id) {
  return "{\"protocolVersion\":1,\"requestId\":\"" +
         std::string(request_id) +
         "\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"" +
         std::string(position_id) + "\"}}";
}

std::string BuildTightenExistingStopRequest(std::string_view request_id,
                                            std::string_view position_id,
                                            std::string_view new_stop_price) {
  return "{\"protocolVersion\":1,\"requestId\":\"" +
         std::string(request_id) +
         "\",\"kind\":\"tightenExistingStop\",\"payload\":{\"positionId\":\"" +
         std::string(position_id) + "\",\"newStopPrice\":\"" +
         std::string(new_stop_price) + "\"}}";
}

bool IsCanonicalManagementResult(std::string_view response,
                                 std::string_view request_id,
                                 bool& completed) noexcept {
  try {
    const std::string prefix =
        "{\"protocolVersion\":1,\"requestId\":\"" +
        std::string(request_id) +
        "\",\"kind\":\"managementResult\",\"payload\":{\"completed\":";
    const std::string failed_before_submit =
        prefix +
        "false,\"submissionAttempted\":false,\"exchangeTruthReconciled\":false}}";
    const std::string failed_unreconciled =
        prefix +
        "false,\"submissionAttempted\":true,\"exchangeTruthReconciled\":false}}";
    const std::string failed_after_reconcile =
        prefix +
        "false,\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";
    const std::string succeeded =
        prefix +
        "true,\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";
    completed = response == succeeded;
    return completed || response == failed_before_submit ||
           response == failed_unreconciled || response == failed_after_reconcile;
  } catch (...) {
    completed = false;
    return false;
  }
}

bool IsCanonicalStatusResponse(std::string_view response,
                               std::string_view request_id) noexcept {
  try {
    constexpr std::string_view kPrefix =
        "{\"protocolVersion\":1,\"requestId\":\"";
    constexpr std::string_view kMiddle =
        "\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"";
    constexpr std::string_view kSuffix = "\",\"entryAuthority\":false}}";
    const std::string expected_prefix =
        std::string(kPrefix) + std::string(request_id) + std::string(kMiddle);
    if (!response.starts_with(expected_prefix) || !response.ends_with(kSuffix)) {
      return false;
    }
    const auto state_length =
        response.size() - expected_prefix.size() - kSuffix.size();
    const auto state = response.substr(expected_prefix.size(), state_length);
    return state == "disarmed" || state == "interrupted" ||
           state == "reconciliationRequired" || state == "manageExistingOnly";
  } catch (...) {
    return false;
  }
}

bool IsCanonicalCredentialReadinessResponse(
    std::string_view response, std::string_view request_id) noexcept {
  try {
    constexpr std::string_view kPrefix =
        "{\"protocolVersion\":1,\"requestId\":\"";
    constexpr std::string_view kMiddle =
        "\",\"kind\":\"credentialReadinessSnapshot\",\"payload\":{\"credentialReadiness\":\"";
    constexpr std::string_view kSuffix = "\",\"entryAuthority\":false}}";
    const std::string expected_prefix =
        std::string(kPrefix) + std::string(request_id) + std::string(kMiddle);
    if (!response.starts_with(expected_prefix) || !response.ends_with(kSuffix)) {
      return false;
    }
    const auto readiness_length =
        response.size() - expected_prefix.size() - kSuffix.size();
    const auto readiness =
        response.substr(expected_prefix.size(), readiness_length);
    return readiness == "missing" || readiness == "ready" ||
           readiness == "incomplete" || readiness == "invalid";
  } catch (...) {
    return false;
  }
}

bool ServicePidMatchesPipeServer(HANDLE pipe) noexcept {
  ULONG server_pid = 0;
  if (!GetNamedPipeServerProcessId(pipe, &server_pid) || server_pid == 0) {
    return false;
  }

  ScopedServiceHandle scm(OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT));
  if (scm.get() == nullptr) {
    return false;
  }
  ScopedServiceHandle service(
      OpenServiceW(scm.get(), kServiceName, SERVICE_QUERY_STATUS));
  if (service.get() == nullptr) {
    return false;
  }

  SERVICE_STATUS_PROCESS status{};
  DWORD bytes_needed = 0;
  if (!QueryServiceStatusEx(service.get(), SC_STATUS_PROCESS_INFO,
                            reinterpret_cast<LPBYTE>(&status), sizeof(status),
                            &bytes_needed)) {
    return false;
  }
  return status.dwCurrentState == SERVICE_RUNNING &&
         status.dwProcessId != 0 && status.dwProcessId == server_pid;
}

bool CompletePendingIo(HANDLE handle, OVERLAPPED& overlapped,
                       DWORD& bytes_transferred,
                       DWORD& win32_error) noexcept {
  if (WaitForSingleObject(overlapped.hEvent, kIoTimeoutMs) != WAIT_OBJECT_0) {
    win32_error = ERROR_TIMEOUT;
    if (!CancelIoEx(handle, &overlapped)) {
      const DWORD cancel_error = GetLastError();
      if (cancel_error != ERROR_NOT_FOUND) {
        win32_error = cancel_error;
        return false;
      }
    }
    if (WaitForSingleObject(overlapped.hEvent, kIoTimeoutMs) != WAIT_OBJECT_0) {
      return false;
    }
    return false;
  }
  if (!GetOverlappedResult(handle, &overlapped, &bytes_transferred, FALSE)) {
    win32_error = GetLastError();
    return false;
  }
  win32_error = ERROR_SUCCESS;
  return true;
}

bool ExchangeStatusFrame(HANDLE pipe, std::string_view request,
                         std::string& response,
                         DWORD& win32_error) noexcept {
  response.clear();
  win32_error = ERROR_SUCCESS;
  if (request.empty() || request.size() > kMaxFrameBytes) {
    win32_error = ERROR_INVALID_DATA;
    return false;
  }

  std::vector<char> buffer(kMaxFrameBytes);
  ScopedHandle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (event.get() == nullptr) {
    win32_error = GetLastError();
    return false;
  }

  OVERLAPPED overlapped{};
  overlapped.hEvent = event.get();
  DWORD bytes_read = 0;
  const BOOL completed = TransactNamedPipe(
      pipe, const_cast<char*>(request.data()), static_cast<DWORD>(request.size()),
      buffer.data(), static_cast<DWORD>(buffer.size()), &bytes_read, &overlapped);
  if (completed == FALSE) {
    const DWORD error = GetLastError();
    if (error == ERROR_MORE_DATA || error != ERROR_IO_PENDING) {
      win32_error = error;
      return false;
    }
    bytes_read = 0;
    if (!CompletePendingIo(pipe, overlapped, bytes_read, win32_error)) {
      return false;
    }
  }

  if (bytes_read == 0 || bytes_read > kMaxFrameBytes) {
    win32_error = ERROR_INVALID_DATA;
    return false;
  }
  buffer.resize(bytes_read);
  response.assign(buffer.begin(), buffer.end());
  return true;
}

bool ConfigureAndVerifyPipe(HANDLE pipe) noexcept {
  DWORD mode = PIPE_READMODE_MESSAGE;
  return SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr) &&
         ServicePidMatchesPipeServer(pipe);
}

int RunReadOnlyQuery(bool credential_readiness) {
  if (!WaitNamedPipeW(kStatusPipeName, kIoTimeoutMs)) {
    std::cerr << "Quantara Windows service status pipe is unavailable.\n";
    return 2;
  }

  ScopedHandle pipe(CreateFileW(kStatusPipeName, GENERIC_READ | GENERIC_WRITE, 0,
                                nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED,
                                nullptr));
  if (pipe.get() == INVALID_HANDLE_VALUE) {
    std::cerr << "Unable to connect to Quantara Windows service status pipe.\n";
    return 3;
  }
  if (!ConfigureAndVerifyPipe(pipe.get())) {
    std::cerr << "Quantara Windows service peer identity could not be verified.\n";
    return 5;
  }

  const std::string request_id = BuildRequestId();
  const std::string request = credential_readiness
                                  ? BuildCredentialReadinessRequest(request_id)
                                  : BuildStatusRequest(request_id);
  std::string response;
  DWORD exchange_error = ERROR_SUCCESS;
  if (!ExchangeStatusFrame(pipe.get(), request, response, exchange_error)) {
    std::cerr << "Quantara Windows service status exchange failed with Win32 error "
              << exchange_error << ".\n";
    return 6;
  }
  const bool valid = credential_readiness
                         ? IsCanonicalCredentialReadinessResponse(response,
                                                                  request_id)
                         : IsCanonicalStatusResponse(response, request_id);
  if (!valid) {
    std::cerr << "Quantara Windows service read-only response failed validation ("
              << response.size() << " bytes).\n";
    return 7;
  }
  std::cout << response << '\n';
  return 0;
}

int RunManagementRequest(std::string_view request, std::string_view request_id) {
  if (!WaitNamedPipeW(kStatusPipeName, kIoTimeoutMs)) {
    std::cerr << "Quantara Windows service status/control pipe is unavailable.\n";
    return 2;
  }

  ScopedHandle pipe(CreateFileW(kStatusPipeName, GENERIC_READ | GENERIC_WRITE, 0,
                                nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED,
                                nullptr));
  if (pipe.get() == INVALID_HANDLE_VALUE) {
    std::cerr << "Unable to connect to Quantara Windows service status/control pipe.\n";
    return 3;
  }
  if (!ConfigureAndVerifyPipe(pipe.get())) {
    std::cerr << "Quantara Windows service peer identity could not be verified.\n";
    return 5;
  }

  std::string response;
  DWORD exchange_error = ERROR_SUCCESS;
  if (!ExchangeStatusFrame(pipe.get(), request, response, exchange_error)) {
    std::cerr << "Quantara Windows management exchange failed with Win32 error "
              << exchange_error << ".\n";
    return 6;
  }

  bool completed = false;
  if (!IsCanonicalManagementResult(response, request_id, completed)) {
    std::cerr << "Quantara Windows management response failed validation ("
              << response.size() << " bytes).\n";
    return 7;
  }
  std::cout << response << '\n';
  return completed ? 0 : 8;
}

int RunCloseExistingPosition(std::wstring_view position_id) {
  if (!IsCanonicalPositionId(position_id)) {
    std::cerr << "Position ID must contain 1-64 decimal digits and must not be zero.\n";
    return 64;
  }
  const std::string request_id = BuildRequestId();
  return RunManagementRequest(
      BuildCloseExistingPositionRequest(request_id, NarrowPositionId(position_id)),
      request_id);
}

int RunTightenExistingStop(std::wstring_view position_id,
                           std::wstring_view new_stop_price) {
  if (!IsCanonicalPositionId(position_id)) {
    std::cerr << "Position ID must contain 1-64 decimal digits and must not be zero.\n";
    return 64;
  }
  const auto price = CanonicalPositiveFinitePrice(new_stop_price);
  if (!price.has_value()) {
    std::cerr << "New stop price must be a positive finite numeric value.\n";
    return 64;
  }
  const std::string request_id = BuildRequestId();
  return RunManagementRequest(
      BuildTightenExistingStopRequest(request_id, NarrowPositionId(position_id),
                                      *price),
      request_id);
}

int RunSelfTest() {
  const std::string status_request = BuildStatusRequest("self-test.1");
  const std::string expected_status_request =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.1\","
      "\"kind\":\"statusRequest\",\"payload\":{}}";
  const std::string readiness_request =
      BuildCredentialReadinessRequest("self-test.2");
  const std::string expected_readiness_request =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.2\","
      "\"kind\":\"credentialReadinessRequest\",\"payload\":{}}";
  const std::string close_request =
      BuildCloseExistingPositionRequest("self-test.3", "123456789");
  const std::string expected_close_request =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.3\","
      "\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"123456789\"}}";
  const std::string tighten_request =
      BuildTightenExistingStopRequest("self-test.4", "123456789", "65000.5");
  const std::string expected_tighten_request =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.4\","
      "\"kind\":\"tightenExistingStop\",\"payload\":{\"positionId\":\"123456789\","
      "\"newStopPrice\":\"65000.5\"}}";
  const std::string valid_status_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.1\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"disarmed\",\"entryAuthority\":false}}";
  const std::string valid_management_status_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.1\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"manageExistingOnly\",\"entryAuthority\":false}}";
  const std::string unsafe_management_status_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.1\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"manageExistingOnly\",\"entryAuthority\":true}}";
  const std::string valid_readiness_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.2\","
      "\"kind\":\"credentialReadinessSnapshot\",\"payload\":{"
      "\"credentialReadiness\":\"ready\",\"entryAuthority\":false}}";
  const std::string invalid_readiness_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.2\","
      "\"kind\":\"credentialReadinessSnapshot\",\"payload\":{"
      "\"credentialReadiness\":\"ready\",\"entryAuthority\":true}}";
  const std::string mismatched_status_response =
      "{\"protocolVersion\":1,\"requestId\":\"other\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"disarmed\",\"entryAuthority\":false}}";
  const std::string completed_management_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.3\","
      "\"kind\":\"managementResult\",\"payload\":{\"completed\":true,"
      "\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";
  const std::string failed_management_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.3\","
      "\"kind\":\"managementResult\",\"payload\":{\"completed\":false,"
      "\"submissionAttempted\":true,\"exchangeTruthReconciled\":true}}";
  const std::string unsafe_management_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.3\","
      "\"kind\":\"managementResult\",\"payload\":{\"completed\":true,"
      "\"submissionAttempted\":false,\"exchangeTruthReconciled\":false}}";
  bool completed = false;
  const bool completed_valid = IsCanonicalManagementResult(
      completed_management_response, "self-test.3", completed);
  const bool completed_flag = completed;
  completed = true;
  const bool failed_valid = IsCanonicalManagementResult(
      failed_management_response, "self-test.3", completed);
  const bool failed_flag = completed;
  completed = false;
  const bool unsafe_valid = IsCanonicalManagementResult(
      unsafe_management_response, "self-test.3", completed);
  const auto valid_price = CanonicalPositiveFinitePrice(L"65000.5");

  if (status_request != expected_status_request ||
      readiness_request != expected_readiness_request ||
      close_request != expected_close_request ||
      tighten_request != expected_tighten_request ||
      status_request.size() > kMaxFrameBytes ||
      readiness_request.size() > kMaxFrameBytes ||
      close_request.size() > kMaxFrameBytes ||
      tighten_request.size() > kMaxFrameBytes ||
      !IsCanonicalPositionId(L"123456789") || IsCanonicalPositionId(L"0") ||
      IsCanonicalPositionId(L"12x") || !valid_price.has_value() ||
      *valid_price != "65000.5" ||
      CanonicalPositiveFinitePrice(L"0").has_value() ||
      CanonicalPositiveFinitePrice(L"nan").has_value() ||
      CanonicalPositiveFinitePrice(L"inf").has_value() ||
      CanonicalPositiveFinitePrice(L"65000.5 extra").has_value() ||
      !IsCanonicalStatusResponse(valid_status_response, "self-test.1") ||
      !IsCanonicalStatusResponse(valid_management_status_response,
                                 "self-test.1") ||
      IsCanonicalStatusResponse(unsafe_management_status_response,
                                "self-test.1") ||
      IsCanonicalStatusResponse(mismatched_status_response, "self-test.1") ||
      !IsCanonicalCredentialReadinessResponse(valid_readiness_response,
                                               "self-test.2") ||
      IsCanonicalCredentialReadinessResponse(invalid_readiness_response,
                                              "self-test.2") ||
      !completed_valid || !completed_flag || !failed_valid || failed_flag ||
      unsafe_valid) {
    std::cerr << "Windows service status/control client self-test failed.\n";
    return 1;
  }
  return 0;
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc == 2 && std::wstring_view(argv[1]) == L"--self-test") {
    return RunSelfTest();
  }
  if (argc == 2 && std::wstring_view(argv[1]) == L"--status") {
    return RunReadOnlyQuery(false);
  }
  if (argc == 2 &&
      std::wstring_view(argv[1]) == L"--credential-readiness") {
    return RunReadOnlyQuery(true);
  }
  if (argc == 3 &&
      std::wstring_view(argv[1]) == L"--close-existing-position") {
    return RunCloseExistingPosition(argv[2]);
  }
  if (argc == 4 &&
      std::wstring_view(argv[1]) == L"--tighten-existing-stop") {
    return RunTightenExistingStop(argv[2], argv[3]);
  }
  std::cerr << "Usage: quantara_windows_service_client.exe "
               "--status|--credential-readiness|--close-existing-position <positionId>|"
               "--tighten-existing-stop <positionId> <newStopPrice>\n";
  return 64;
}
