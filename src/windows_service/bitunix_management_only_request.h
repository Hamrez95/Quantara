#pragma once

#include "../native/execution/existing_position_management_policy.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <cctype>
#include <optional>
#include <string>
#include <string_view>

namespace quantara {

struct BitunixManagementOnlyHttpRequest final {
  std::string method;
  std::string path;
  std::string body;
};

namespace detail {

[[nodiscard]] inline bool IsSafeNumericPositionId(std::string_view value) noexcept {
  return !value.empty() && value.size() <= 128 &&
      std::all_of(value.begin(), value.end(), [](const char ch) {
        return std::isdigit(static_cast<unsigned char>(ch)) != 0;
      });
}

[[nodiscard]] inline bool IsSafeSymbol(std::string_view value) noexcept {
  return !value.empty() && value.size() <= 32 &&
      std::all_of(value.begin(), value.end(), [](const char ch) {
        return std::isalnum(static_cast<unsigned char>(ch)) != 0 || ch == '_' ||
               ch == '-';
      });
}

[[nodiscard]] inline bool IsSupportedStopTriggerType(
    std::string_view value) noexcept {
  return value == "LAST_PRICE" || value == "MARK_PRICE";
}

[[nodiscard]] inline std::optional<std::string> SerializePositivePrice(
    double value) noexcept {
  if (!std::isfinite(value) || value <= 0.0) return std::nullopt;

  std::array<char, 64> buffer{};
  const auto result = std::to_chars(buffer.data(), buffer.data() + buffer.size(),
                                    value, std::chars_format::general);
  if (result.ec != std::errc{}) return std::nullopt;
  return std::string(buffer.data(), result.ptr);
}

}  // namespace detail

// Builds only exchange requests that manage one already-verified position.
// This boundary intentionally has no new-entry, leverage, margin, withdrawal,
// transfer, generic-order, stop-widening or averaging-down endpoint.
[[nodiscard]] inline std::optional<BitunixManagementOnlyHttpRequest>
BuildBitunixManagementOnlyRequest(
    const ExistingPositionMutationRequest& request) noexcept {
  if (!request.reduce_only || request.increases_exposure ||
      request.changes_margin_mode || request.widens_stop ||
      !detail::IsSafeNumericPositionId(request.position_id)) {
    return std::nullopt;
  }

  switch (request.kind) {
    case ExistingPositionMutationKind::kReduceOnlyClose:
      return BitunixManagementOnlyHttpRequest{
          .method = "POST",
          .path = "/api/v1/futures/trade/flash_close_position",
          .body = "{\"positionId\":\"" + std::string(request.position_id) + "\"}",
      };

    case ExistingPositionMutationKind::kTightenStop: {
      if (!detail::IsSafeSymbol(request.symbol) ||
          !detail::IsSupportedStopTriggerType(request.stop_trigger_type)) {
        return std::nullopt;
      }
      const auto price = detail::SerializePositivePrice(request.new_stop_price);
      if (!price.has_value()) return std::nullopt;

      return BitunixManagementOnlyHttpRequest{
          .method = "POST",
          .path = "/api/v1/futures/tpsl/position/modify_order",
          .body = "{\"symbol\":\"" + std::string(request.symbol) +
              "\",\"positionId\":\"" + std::string(request.position_id) +
              "\",\"slPrice\":\"" + *price + "\",\"slStopType\":\"" +
              std::string(request.stop_trigger_type) + "\"}",
      };
    }

    case ExistingPositionMutationKind::kUnsupported:
      return std::nullopt;
  }

  return std::nullopt;
}

}  // namespace quantara
