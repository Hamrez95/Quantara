#include <windows.h>
#include <winsvc.h>

#include <cstdint>
#include <iostream>
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
           state == "reconciliationRequired";
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

bool CompleteOverlappedIo(HANDLE handle, OVERLAPPED& overlapped,
                          DWORD& bytes_transferred) noexcept {
  const DWORD wait_result = WaitForSingleObject(overlapped.hEvent, kIoTimeoutMs);
  if (wait_result != WAIT_OBJECT_0) {
    if (!CancelIoEx(handle, &overlapped)) {
      const DWORD cancel_error = GetLastError();
      if (cancel_error != ERROR_NOT_FOUND) {
        return false;
      }
    }
    if (WaitForSingleObject(overlapped.hEvent, kIoTimeoutMs) != WAIT_OBJECT_0) {
      return false;
    }
    return false;
  }
  return GetOverlappedResult(handle, &overlapped, &bytes_transferred, FALSE) ==
         TRUE;
}

bool WriteBoundedFrame(HANDLE pipe, std::string_view frame) noexcept {
  if (frame.empty() || frame.size() > kMaxFrameBytes) {
    return false;
  }
  ScopedHandle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (event.get() == nullptr) {
    return false;
  }
  OVERLAPPED overlapped{};
  overlapped.hEvent = event.get();
  DWORD bytes_written = 0;
  const BOOL wrote = WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()),
                               &bytes_written, &overlapped);
  if (wrote == FALSE) {
    if (GetLastError() != ERROR_IO_PENDING ||
        !CompleteOverlappedIo(pipe, overlapped, bytes_written)) {
      return false;
    }
  }
  return bytes_written == frame.size();
}

bool ReadBoundedFrame(HANDLE pipe, std::string& frame) noexcept {
  std::vector<char> buffer(kMaxFrameBytes);
  ScopedHandle event(CreateEventW(nullptr, TRUE, FALSE, nullptr));
  if (event.get() == nullptr) {
    return false;
  }
  OVERLAPPED overlapped{};
  overlapped.hEvent = event.get();
  DWORD bytes_read = 0;
  const BOOL read = ReadFile(pipe, buffer.data(), static_cast<DWORD>(buffer.size()),
                             &bytes_read, &overlapped);
  if (read == FALSE) {
    const DWORD error = GetLastError();
    if (error == ERROR_MORE_DATA || error != ERROR_IO_PENDING ||
        !CompleteOverlappedIo(pipe, overlapped, bytes_read)) {
      return false;
    }
  }
  if (bytes_read == 0 || bytes_read > kMaxFrameBytes) {
    return false;
  }
  frame.assign(buffer.data(), bytes_read);
  return true;
}

int RunStatusQuery() {
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

  DWORD mode = PIPE_READMODE_MESSAGE;
  if (!SetNamedPipeHandleState(pipe.get(), &mode, nullptr, nullptr)) {
    std::cerr << "Unable to configure Quantara Windows service status pipe.\n";
    return 4;
  }
  if (!ServicePidMatchesPipeServer(pipe.get())) {
    std::cerr << "Quantara Windows service peer identity could not be verified.\n";
    return 5;
  }

  const std::string request_id = BuildRequestId();
  const std::string request = BuildStatusRequest(request_id);
  if (!WriteBoundedFrame(pipe.get(), request)) {
    std::cerr << "Quantara Windows service status request failed.\n";
    return 6;
  }

  std::string response;
  if (!ReadBoundedFrame(pipe.get(), response) ||
      !IsCanonicalStatusResponse(response, request_id)) {
    std::cerr << "Quantara Windows service status response failed validation.\n";
    return 7;
  }
  std::cout << response << '\n';
  return 0;
}

int RunSelfTest() {
  const std::string request = BuildStatusRequest("self-test.1");
  const std::string expected =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.1\","
      "\"kind\":\"statusRequest\",\"payload\":{}}";
  const std::string valid_response =
      "{\"protocolVersion\":1,\"requestId\":\"self-test.1\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"disarmed\",\"entryAuthority\":false}}";
  const std::string mismatched_response =
      "{\"protocolVersion\":1,\"requestId\":\"other\","
      "\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":"
      "\"disarmed\",\"entryAuthority\":false}}";
  if (request != expected || request.size() > kMaxFrameBytes ||
      !IsCanonicalStatusResponse(valid_response, "self-test.1") ||
      IsCanonicalStatusResponse(mismatched_response, "self-test.1")) {
    std::cerr << "Windows service status client self-test failed.\n";
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
    return RunStatusQuery();
  }
  std::cerr << "Usage: quantara_windows_service_client.exe --status\n";
  return 64;
}
