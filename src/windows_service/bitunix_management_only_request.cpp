#include "bitunix_management_only_request.h"

#include <algorithm>
#include <cctype>

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
      request.may_open_new_exposure || request.may_increase_exposure ||
      request.may_widen_risk || request.may_change_margin_mode ||
      !IsSafePositionId(request.position_id)) {
    return std::nullopt;
  }

  // Bitunix OpenAPI: POST /api/v1/futures/trade/flash_close_position with an
  // exact positionId. No generic order endpoint is reachable through this
  // builder, so the request cannot accidentally become an entry order.
  return BitunixManagementOnlyHttpRequest{
      .method = "POST",
      .path = "/api/v1/futures/trade/flash_close_position",
      .body = "{\"positionId\":\"" + request.position_id + "\"}",
  };
}

}  // namespace quantara
