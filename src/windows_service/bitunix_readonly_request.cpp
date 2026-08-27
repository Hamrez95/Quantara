#include "bitunix_readonly_request.h"

#include <algorithm>
#include <cctype>
#include <string>
#include <unordered_set>

namespace quantara {
namespace {

constexpr std::string_view kHost = "fapi.bitunix.com";
constexpr std::string_view kPendingPositionsPath =
    "/api/v1/futures/position/get_pending_positions";
constexpr std::string_view kPendingOrdersPath =
    "/api/v1/futures/trade/get_pending_orders";
constexpr std::size_t kMaxQueryPairs = 8;
constexpr std::size_t kMaxQueryValueLength = 128;
constexpr std::size_t kMaxHeaderValueLength = 256;

bool IsSafeValue(std::string_view value) noexcept {
  if (value.empty() || value.size() > kMaxQueryValueLength) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char c) {
    return c >= 0x21 && c <= 0x7e && c != '&' && c != '=' && c != '#';
  });
}

bool IsSafeHeaderValue(std::string_view value) noexcept {
  if (value.empty() || value.size() > kMaxHeaderValueLength) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char c) {
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
           return std::isxdigit(c) != 0;
         });
}

bool IsAllowedKey(BitunixReadOnlyEndpoint endpoint, std::string_view key) noexcept {
  switch (endpoint) {
    case BitunixReadOnlyEndpoint::kPendingPositions:
      return key == "symbol" || key == "positionId";
    case BitunixReadOnlyEndpoint::kPendingOrders:
      return key == "symbol" || key == "orderId" || key == "clientId" ||
             key == "status" || key == "startTime" || key == "endTime" ||
             key == "skip" || key == "limit";
  }
  return false;
}

std::optional<std::string_view> PathFor(BitunixReadOnlyEndpoint endpoint) noexcept {
  switch (endpoint) {
    case BitunixReadOnlyEndpoint::kPendingPositions:
      return kPendingPositionsPath;
    case BitunixReadOnlyEndpoint::kPendingOrders:
      return kPendingOrdersPath;
  }
  return std::nullopt;
}

std::optional<BitunixReadOnlyEndpoint> EndpointForPath(
    std::string_view path) noexcept {
  if (path == kPendingPositionsPath) {
    return BitunixReadOnlyEndpoint::kPendingPositions;
  }
  if (path == kPendingOrdersPath) {
    return BitunixReadOnlyEndpoint::kPendingOrders;
  }
  return std::nullopt;
}

bool ValidateQuery(
    BitunixReadOnlyEndpoint endpoint,
    const std::vector<std::pair<std::string, std::string>>& query) noexcept {
  if (query.size() > kMaxQueryPairs) return false;

  std::unordered_set<std::string> seen;
  seen.reserve(query.size());
  for (const auto& [key, value] : query) {
    if (!IsAllowedKey(endpoint, key) || !IsSafeValue(value) ||
        !seen.insert(key).second) {
      return false;
    }
  }
  return true;
}

bool IsUnreserved(unsigned char c) noexcept {
  return std::isalnum(c) != 0 || c == '-' || c == '.' || c == '_' || c == '~';
}

std::string PercentEncode(std::string_view value) {
  constexpr char kHex[] = "0123456789ABCDEF";
  std::string encoded;
  encoded.reserve(value.size());
  for (const unsigned char c : value) {
    if (IsUnreserved(c)) {
      encoded.push_back(static_cast<char>(c));
    } else {
      encoded.push_back('%');
      encoded.push_back(kHex[(c >> 4) & 0x0f]);
      encoded.push_back(kHex[c & 0x0f]);
    }
  }
  return encoded;
}

std::optional<std::string> BuildResource(
    std::string_view path,
    const std::vector<std::pair<std::string, std::string>>& query) {
  std::string resource(path);
  if (query.empty()) return resource;

  resource.push_back('?');
  for (std::size_t index = 0; index < query.size(); ++index) {
    if (index != 0) resource.push_back('&');
    resource.append(PercentEncode(query[index].first));
    resource.push_back('=');
    resource.append(PercentEncode(query[index].second));
  }
  return resource;
}

}  // namespace

std::optional<BitunixReadOnlyRequest> BuildBitunixReadOnlyRequest(
    const std::filesystem::path& credential_root, BitunixReadOnlyEndpoint endpoint,
    std::string_view nonce, std::string_view timestamp,
    const std::vector<std::pair<std::string, std::string>>& query) noexcept {
  try {
    const auto path = PathFor(endpoint);
    if (!path.has_value() || !ValidateQuery(endpoint, query)) return std::nullopt;

    const auto authorization = AuthorizeBitunixPrivateRequest(
        credential_root, nonce, timestamp, query);
    if (!authorization.has_value()) return std::nullopt;

    return BitunixReadOnlyRequest{std::string(kHost), "GET", std::string(*path),
                                  query, *authorization};
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<BitunixReadOnlyHttpEnvelope> BuildBitunixReadOnlyHttpEnvelope(
    const BitunixReadOnlyRequest& request) noexcept {
  try {
    if (request.host != kHost || request.method != "GET") return std::nullopt;

    const auto endpoint = EndpointForPath(request.path);
    if (!endpoint.has_value() || !ValidateQuery(*endpoint, request.query)) {
      return std::nullopt;
    }

    const auto& authorization = request.authorization;
    if (!IsSafeHeaderValue(authorization.api_key) ||
        !IsSafeHeaderValue(authorization.nonce) ||
        !IsDecimalTimestamp(authorization.timestamp) ||
        !IsSha256Hex(authorization.sign)) {
      return std::nullopt;
    }

    const auto resource = BuildResource(request.path, request.query);
    if (!resource.has_value()) return std::nullopt;

    std::vector<std::pair<std::string, std::string>> headers{
        {"api-key", authorization.api_key},
        {"nonce", authorization.nonce},
        {"timestamp", authorization.timestamp},
        {"sign", authorization.sign},
        {"Content-Type", "application/json"},
    };

    return BitunixReadOnlyHttpEnvelope{request.host, request.method, *resource,
                                       std::move(headers)};
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
