#include "bitunix_https_readonly_transport.h"

#include <windows.h>
#include <winhttp.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <limits>
#include <string_view>
#include <unordered_set>
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
constexpr std::size_t kMaxHeaderValueLength = 256;
constexpr std::size_t kMaxResourceLength = 2048;
constexpr std::size_t kMaxEncodedQueryValueLength = 3 * 128;
constexpr std::size_t kMaxQueryPairs = 8;

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

bool IsHex(unsigned char c) noexcept { return std::isxdigit(c) != 0; }

bool IsUnreserved(unsigned char c) noexcept {
  return std::isalnum(c) != 0 || c == '-' || c == '.' || c == '_' || c == '~';
}

bool IsValidEncodedValue(std::string_view value) noexcept {
  if (value.empty() || value.size() > kMaxEncodedQueryValueLength) return false;
  for (std::size_t i = 0; i < value.size(); ++i) {
    const auto c = static_cast<unsigned char>(value[i]);
    if (IsUnreserved(c)) continue;
    if (c != '%' || i + 2 >= value.size() ||
        !IsHex(static_cast<unsigned char>(value[i + 1])) ||
        !IsHex(static_cast<unsigned char>(value[i + 2]))) {
      return false;
    }
    i += 2;
  }
  return true;
}

bool IsAllowedQueryKey(std::string_view path, std::string_view key) noexcept {
  if (path == kPositionsPath) {
    return key == "symbol" || key == "positionId";
  }
  if (path == kOrdersPath) {
    return key == "symbol" || key == "orderId" || key == "clientId" ||
           key == "status" || key == "startTime" || key == "endTime" ||
           key == "skip" || key == "limit";
  }
  return false;
}

bool IsAllowedResource(std::string_view resource) noexcept {
  if (resource.empty() || resource.size() > kMaxResourceLength ||
      resource.front() != '/' || resource.find_first_of("\r\n#") != std::string_view::npos) {
    return false;
  }

  const auto query_pos = resource.find('?');
  const auto path = resource.substr(0, query_pos);
  if (path != kPositionsPath && path != kOrdersPath) return false;
  if (query_pos == std::string_view::npos) return true;

  auto query = resource.substr(query_pos + 1);
  if (query.empty()) return false;
  std::unordered_set<std::string_view> seen;
  std::size_t pair_count = 0;
  while (!query.empty()) {
    const auto amp = query.find('&');
    const auto pair = query.substr(0, amp);
    const auto equals = pair.find('=');
    if (equals == std::string_view::npos || equals == 0 || equals + 1 >= pair.size()) {
      return false;
    }
    const auto key = pair.substr(0, equals);
    const auto value = pair.substr(equals + 1);
    ++pair_count;
    if (pair_count > kMaxQueryPairs || !IsAllowedQueryKey(path, key) ||
        !IsValidEncodedValue(value) || !seen.insert(key).second) {
      return false;
    }
    if (amp == std::string_view::npos) break;
    query.remove_prefix(amp + 1);
    if (query.empty()) return false;
  }
  return true;
}

bool IsPrintableAsciiValue(std::string_view value) noexcept {
  return !value.empty() && value.size() <= kMaxHeaderValueLength &&
         std::all_of(value.begin(), value.end(), [](unsigned char c) {
           return c >= 0x21 && c <= 0x7e;
         });
}

bool IsDecimalTimestamp(std::string_view value) noexcept {
  return !value.empty() && value.size() <= 20 &&
         std::all_of(value.begin(), value.end(), [](unsigned char c) {
           return std::isdigit(c) != 0;
         });
}

bool IsSha256Hex(std::string_view value) noexcept {
  return value.size() == 64 &&
         std::all_of(value.begin(), value.end(), [](unsigned char c) {
           return IsHex(c);
         });
}

std::optional<std::string_view> HeaderValue(
    const std::vector<std::pair<std::string, std::string>>& headers,
    std::string_view name) noexcept {
  const auto it = std::find_if(headers.begin(), headers.end(), [&](const auto& header) {
    return header.first == name;
  });
  if (it == headers.end()) return std::nullopt;
  return it->second;
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

  const auto api_key = HeaderValue(headers, "api-key");
  const auto nonce = HeaderValue(headers, "nonce");
  const auto timestamp = HeaderValue(headers, "timestamp");
  const auto sign = HeaderValue(headers, "sign");
  const auto content_type = HeaderValue(headers, "Content-Type");
  return api_key.has_value() && nonce.has_value() && timestamp.has_value() &&
         sign.has_value() && content_type.has_value() &&
         IsPrintableAsciiValue(*api_key) && IsPrintableAsciiValue(*nonce) &&
         IsDecimalTimestamp(*timestamp) && IsSha256Hex(*sign) &&
         *content_type == "application/json";
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
    constexpr auto kMaxInt = static_cast<unsigned long>((std::numeric_limits<int>::max)());
    if (!ValidateBitunixHttpsReadOnlyEnvelope(envelope) ||
        limits.connect_timeout_ms == 0 || limits.send_timeout_ms == 0 ||
        limits.receive_timeout_ms == 0 || limits.connect_timeout_ms > kMaxInt ||
        limits.send_timeout_ms > kMaxInt || limits.receive_timeout_ms > kMaxInt ||
        limits.max_body_bytes == 0 || limits.max_body_bytes > 4 * 1024 * 1024) {
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
      const auto available_size = static_cast<std::size_t>(available);
      if (available_size > limits.max_body_bytes - body.size()) return std::nullopt;
      std::vector<char> buffer(available_size);
      DWORD read = 0;
      if (!WinHttpReadData(request.get(), buffer.data(), available, &read) || read == 0) {
        return std::nullopt;
      }
      const auto read_size = static_cast<std::size_t>(read);
      if (read_size > limits.max_body_bytes - body.size()) return std::nullopt;
      body.append(buffer.data(), read_size);
    }

    return BitunixHttpsReadOnlyResponse{status_code, std::move(body)};
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
