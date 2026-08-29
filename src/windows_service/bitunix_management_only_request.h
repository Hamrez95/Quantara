#pragma once

#include "../native/execution/existing_position_management_policy.h"

#include <algorithm>
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

// Builds only the exchange request that can close one already-verified position.
// This boundary intentionally has no new-entry, leverage, margin, or generic order
// endpoint. Stop tightening is not serialized here until its symbol/price payload
// is represented explicitly by the shared mutation contract.
[[nodiscard]] inline std::optional<BitunixManagementOnlyHttpRequest>
BuildBitunixManagementOnlyRequest(
    const ExistingPositionMutationRequest& request) noexcept {
  const auto safe_position_id = !request.position_id.empty() &&
      std::all_of(request.position_id.begin(), request.position_id.end(),
                  [](const char ch) {
                    return std::isdigit(static_cast<unsigned char>(ch)) != 0;
                  });
  if (request.kind != ExistingPositionMutationKind::kReduceOnlyClose ||
      !request.reduce_only || request.increases_exposure ||
      request.changes_margin_mode || request.widens_stop || !safe_position_id) {
    return std::nullopt;
  }

  return BitunixManagementOnlyHttpRequest{
      .method = "POST",
      .path = "/api/v1/futures/trade/flash_close_position",
      .body = "{\"positionId\":\"" + std::string(request.position_id) + "\"}",
  };
}

}  // namespace quantara
