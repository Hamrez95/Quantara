#include "bitunix_management_only_https_transport.h"

#include <windows.h>
#include <winhttp.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <limits>
#include <string_view>
#include <vector>

namespace quantara {
namespace {

constexpr std::string_view kHost = "fapi.bitunix.com";
constexpr std::string_view kClosePath =
    "/api/v1/futures/trade/flash_close_position";
constexpr std::array<std::string_view, 5> kRequiredHeaders{
    "api-key", "nonce", "timestamp", "sign", "Content-Type"};
constexpr std::size_t kMaxHeaderValueLength = 256;
constexpr std::size_t kMaxRequestBodyBytes = 512;

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

bool IsValidCloseBody(std::string_view body) noexcept {
  if (body.empty() || body.size() > kMaxRequestBodyBytes) return false;
  constexpr std::string_view kPrefix = "{\"positionId\":\"";
  constexpr std::string_view kSuffix = "\"}";
  if (!body.starts_with(kPrefix) || !body.ends_with(kSuffix) ||
      body.size() <= kPrefix.size() + kSuffix.size()) {
    return false;
  }
  const auto id = body.substr(kPrefix.size(),
                              body.size() - kPrefix.size() - kSuffix.size());
  return !id.empty() &&
         std::all_of(id.begin(), id.end(), [](unsigned char c) {
           return std::isdigit(c) != 0;
         });
}

bool ValidateEnvelope(const BitunixManagementOnlyHttpEnvelope& envelope) noexcept {
  return envelope.host == kHost && envelope.method == "POST" &&
         envelope.resource == kClosePath && IsValidCloseBody(envelope.body) &&
         HasExactRequiredHeaders(envelope.headers);
}

std::optional<std::wstring> Utf8ToWide(std::string_view value) noexcept {
  if (value.empty() ||
      value.size() > static_cast<std::size_t>((std::numeric_limits<int>::max)())) {
    return std::nullopt;
  }
  const int input_size = static_cast<int>(value.size());
  const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            value.data(), input_size, nullptr, 0);
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

std::optional<BitunixManagementOnlyHttpEnvelope>
BuildBitunixManagementOnlyHttpEnvelope(
    const std::filesystem::path& credential_root,
    const BitunixManagementOnlyHttpRequest& request,
    std::string_view nonce,
    std::string_view timestamp) noexcept {
  try {
    if (credential_root.empty() || request.method != "POST" ||
        request.path != kClosePath || !IsValidCloseBody(request.body) ||
        nonce.empty() || timestamp.empty()) {
      return std::nullopt;
    }

    const auto authorization = AuthorizeBitunixPrivateRequest(
        credential_root, nonce, timestamp, {}, request.body);
    if (!authorization.has_value()) return std::nullopt;

    std::vector<std::pair<std::string, std::string>> headers{
        {"api-key", authorization->api_key},
        {"nonce", authorization->nonce},
        {"timestamp", authorization->timestamp},
        {"sign", authorization->sign},
        {"Content-Type", "application/json"},
    };

    BitunixManagementOnlyHttpEnvelope envelope{
        std::string(kHost), request.method, request.path, request.body,
        std::move(headers)};
    if (!ValidateEnvelope(envelope)) return std::nullopt;
    return envelope;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<BitunixManagementOnlyHttpsResponse>
ExecuteBitunixManagementOnlyHttps(
    const BitunixManagementOnlyHttpEnvelope& envelope,
    const BitunixManagementOnlyHttpsLimits& limits) noexcept {
  try {
    constexpr auto kMaxInt =
        static_cast<unsigned long>((std::numeric_limits<int>::max)());
    if (!ValidateEnvelope(envelope) || limits.connect_timeout_ms == 0 ||
        limits.send_timeout_ms == 0 || limits.receive_timeout_ms == 0 ||
        limits.connect_timeout_ms > kMaxInt || limits.send_timeout_ms > kMaxInt ||
        limits.receive_timeout_ms > kMaxInt || limits.max_body_bytes == 0 ||
        limits.max_body_bytes > 4 * 1024 * 1024 ||
        envelope.body.size() > static_cast<std::size_t>((std::numeric_limits<DWORD>::max)())) {
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
        connection.get(), L"POST", resource->c_str(), nullptr, WINHTTP_NO_REFERER,
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

    auto* body = const_cast<char*>(envelope.body.data());
    const auto body_size = static_cast<DWORD>(envelope.body.size());
    if (!WinHttpSendRequest(request.get(), WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            body, body_size, body_size, 0) ||
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

    std::string response_body;
    while (true) {
      DWORD available = 0;
      if (!WinHttpQueryDataAvailable(request.get(), &available)) return std::nullopt;
      if (available == 0) break;
      const auto available_size = static_cast<std::size_t>(available);
      if (available_size > limits.max_body_bytes - response_body.size()) {
        return std::nullopt;
      }
      std::vector<char> buffer(available_size);
      DWORD read = 0;
      if (!WinHttpReadData(request.get(), buffer.data(), available, &read) || read == 0) {
        return std::nullopt;
      }
      const auto read_size = static_cast<std::size_t>(read);
      if (read_size > limits.max_body_bytes - response_body.size()) {
        return std::nullopt;
      }
      response_body.append(buffer.data(), read_size);
    }

    return BitunixManagementOnlyHttpsResponse{status_code,
                                               std::move(response_body)};
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
