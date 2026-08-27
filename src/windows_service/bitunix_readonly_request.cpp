#include "bitunix_readonly_request.h"

#include <algorithm>
#include <array>
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

bool IsSafeValue(std::string_view value) noexcept {
  if (value.empty() || value.size() > kMaxQueryValueLength) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char c) {
    return c >= 0x21 && c <= 0x7e && c != '&' && c != '=' && c != '#';
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

}  // namespace quantara
