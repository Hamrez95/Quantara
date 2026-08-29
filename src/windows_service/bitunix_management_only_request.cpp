#include "bitunix_management_only_request.h"

#include <algorithm>
#include <cctype>
#include <string_view>

namespace quantara {
namespace {

bool IsSafePositionId(const std::string_view value) noexcept {
  if (value.empty()) {
    return false;
  }
  return std::all_of(value.begin(), value.end(), [](const char ch) {
    return std::isdigit(static_cast<unsigned char>(ch)) != 0;
  });
}

}  // namespace

std::optional<BitunixManagementOnlyHttpRequest>
BuildBitunixManagementOnlyRequest(
    const ExistingPositionMutationRequest& request) noexcept {
  if (request.kind != ExistingPositionMutationKind::kReduceOnlyClose ||
      !request.reduce_only || request.increases_exposure ||
      request.changes_margin_mode || request.widens_stop ||
      !IsSafePositionId(request.position_id)) {
    return std::nullopt;
  }

  // Bitunix OpenAPI: POST /api/v1/futures/trade/flash_close_position with an
  // exact positionId. No generic order endpoint is reachable through this
  // builder, so the request cannot accidentally become an entry order.
  return BitunixManagementOnlyHttpRequest{
      .method = "POST",
      .path = "/api/v1/futures/trade/flash_close_position",
      .body = "{\"positionId\":\"" + std::string(request.position_id) + "\"}",
  };
}

}  // namespace quantara
