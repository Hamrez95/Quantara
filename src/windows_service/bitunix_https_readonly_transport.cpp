#include "bitunix_https_readonly_transport.h"

#include <windows.h>
#include <winhttp.h>

#include <algorithm>
#include <array>
#include <limits>
#include <string_view>
#include <vector>

namespace quantara {
namespace {

constexpr std::string_view kHost = "fapi.bitunix.com";
constexpr std::string_view kPositionsPath =
    "/api/v1/futures/position/get_pending_positions";
constexpr std::string_view kOrdersPath =
    "/api/v1/futures/trade/get_pending_orders";
constexpr std::array<std::string_view, 5> kRequiredHeaders{
    "api-key", "nonce", "timestamp", "sign", "Content-Type"};

class WinHttpHandle final {
 public:
  explicit WinHttpHandle(HINTERNET handle = nullptr) noexcept : handle_(handle) {}
  ~WinHttpHandle() {
    if (handle_ != nullptr) WinHttpCloseHandle(handle_);
  }
  WinHttpHandle(const WinHttpHandle&) = delete;
  WinHttpHandle& operator=(const WinHttpHandle&) = delete;
  HINTERNET get() const noexcept { return handle_; }
  explicit operator bool() const noexcept { return handle_ != nullptr; }

 private:
  HINTERNET handle_;
};

bool IsAllowedResource(std::string_view resource) noexcept {
  const auto query = resource.find('?');
  const auto path = resource.substr(0, query);
  if (path != kPositionsPath && path != kOrdersPath) return false;
  return resource.find('\r') == std::string_view::npos &&
         resource.find('\n') == std::string_view::npos &&
         resource.find('#') == std::string_view::npos &&
         !resource.empty() && resource.front() == '/';
}

bool HasExactRequiredHeaders(
    const std::vector<std::pair<std::string, std::string>>& headers) noexcept {
  if (headers.size() != kRequiredHeaders.size()) return false;
  for (const auto required : kRequiredHeaders) {
    const auto count = std::count_if(headers.begin(), headers.end(),
                                     [&](const auto& header) {
                                       return header.first == required;
                                     });
    if (count != 1) return false;
  }
  for (const auto& [name, value] : headers) {
    if (name.empty() || value.empty() || name.find_first_of("\r\n:") != std::string::npos ||
        value.find_first_of("\r\n") != std::string::npos) {
      return false;
    }
  }
  return true;
}

std::optional<std::wstring> Utf8ToWide(std::string_view value) noexcept {
  if (value.empty() || value.size() > static_cast<std::size_t>((std::numeric_limits<int>::max)())) {
    return std::nullopt;
  }
  const int input_size = static_cast<int>(value.size());
  const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                            input_size, nullptr, 0);
  if (required <= 0) return std::nullopt;
  std::wstring wide(static_cast<std::size_t>(required), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_size,
                          wide.data(), required) != required) {
    return std::nullopt;
  }
  return wide;
}

std::optional<std::wstring> BuildHeaders(
    const std::vector<std::pair<std::string, std::string>>& headers) noexcept {
  try {
    std::wstring result;
    for (const auto& [name, value] : headers) {
      const auto wide_name = Utf8ToWide(name);
      const auto wide_value = Utf8ToWide(value);
      if (!wide_name.has_value() || !wide_value.has_value()) return std::nullopt;
      result.append(*wide_name);
      result.append(L": ");
      result.append(*wide_value);
      result.append(L"\r\n");
    }
    return result;
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace

bool ValidateBitunixHttpsReadOnlyEnvelope(
    const BitunixReadOnlyHttpEnvelope& envelope) noexcept {
  return envelope.host == kHost && envelope.method == "GET" &&
         IsAllowedResource(envelope.resource) &&
         HasExactRequiredHeaders(envelope.headers);
}

std::optional<BitunixHttpsReadOnlyResponse> ExecuteBitunixHttpsReadOnly(
    const BitunixReadOnlyHttpEnvelope& envelope,
    const BitunixHttpsReadOnlyLimits& limits) noexcept {
  try {
    if (!ValidateBitunixHttpsReadOnlyEnvelope(envelope) ||
        limits.connect_timeout_ms == 0 || limits.send_timeout_ms == 0 ||
        limits.receive_timeout_ms == 0 || limits.max_body_bytes == 0 ||
        limits.max_body_bytes > 4 * 1024 * 1024) {
      return std::nullopt;
    }

    const auto host = Utf8ToWide(envelope.host);
    const auto resource = Utf8ToWide(envelope.resource);
    const auto headers = BuildHeaders(envelope.headers);
    if (!host.has_value() || !resource.has_value() || !headers.has_value()) {
      return std::nullopt;
    }

    WinHttpHandle session(WinHttpOpen(L"QuantaraWindowsService/1.0",
                                      WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                      WINHTTP_NO_PROXY_NAME,
                                      WINHTTP_NO_PROXY_BYPASS, 0));
    if (!session) return std::nullopt;

    if (!WinHttpSetTimeouts(session.get(),
                            static_cast<int>(limits.connect_timeout_ms),
                            static_cast<int>(limits.connect_timeout_ms),
                            static_cast<int>(limits.send_timeout_ms),
                            static_cast<int>(limits.receive_timeout_ms))) {
      return std::nullopt;
    }

    WinHttpHandle connection(
        WinHttpConnect(session.get(), host->c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0));
    if (!connection) return std::nullopt;

    WinHttpHandle request(WinHttpOpenRequest(
        connection.get(), L"GET", resource->c_str(), nullptr, WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE));
    if (!request) return std::nullopt;

    DWORD disabled_features = WINHTTP_DISABLE_REDIRECTS;
    if (!WinHttpSetOption(request.get(), WINHTTP_OPTION_DISABLE_FEATURE,
                          &disabled_features, sizeof(disabled_features))) {
      return std::nullopt;
    }

    if (!WinHttpAddRequestHeaders(request.get(), headers->c_str(),
                                  static_cast<DWORD>(headers->size()),
                                  WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE)) {
      return std::nullopt;
    }

    if (!WinHttpSendRequest(request.get(), WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(request.get(), nullptr)) {
      return std::nullopt;
    }

    DWORD status_code = 0;
    DWORD status_size = sizeof(status_code);
    if (!WinHttpQueryHeaders(request.get(),
                             WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size,
                             WINHTTP_NO_HEADER_INDEX) ||
        status_code != 200) {
      return std::nullopt;
    }

    std::string body;
    while (true) {
      DWORD available = 0;
      if (!WinHttpQueryDataAvailable(request.get(), &available)) return std::nullopt;
      if (available == 0) break;
      if (available > limits.max_body_bytes - body.size()) return std::nullopt;
      std::vector<char> buffer(available);
      DWORD read = 0;
      if (!WinHttpReadData(request.get(), buffer.data(), available, &read) || read == 0) {
        return std::nullopt;
      }
      if (read > limits.max_body_bytes - body.size()) return std::nullopt;
      body.append(buffer.data(), read);
    }

    return BitunixHttpsReadOnlyResponse{status_code, std::move(body)};
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
