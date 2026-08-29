#include "bitunix_management_only_request.h"

#include <cassert>

int main() {
  using namespace quantara;

  const ExistingPositionMutationRequest allowed{
      .kind = ExistingPositionMutationKind::kReduceOnlyClose,
      .position_id = "19848247723672",
      .symbol = "BTCUSDT",
      .reduce_only = true,
      .increases_exposure = false,
      .changes_margin_mode = false,
      .widens_stop = false,
  };
  const auto built = BuildBitunixManagementOnlyRequest(allowed);
  assert(built.has_value());
  assert(built->method == "POST");
  assert(built->path == "/api/v1/futures/trade/flash_close_position");
  assert(built->body == "{\"positionId\":\"19848247723672\"}");

  auto unsafe = allowed;
  unsafe.increases_exposure = true;
  assert(!BuildBitunixManagementOnlyRequest(unsafe).has_value());

  unsafe = allowed;
  unsafe.reduce_only = false;
  assert(!BuildBitunixManagementOnlyRequest(unsafe).has_value());

  unsafe = allowed;
  unsafe.changes_margin_mode = true;
  assert(!BuildBitunixManagementOnlyRequest(unsafe).has_value());

  unsafe = allowed;
  unsafe.widens_stop = true;
  assert(!BuildBitunixManagementOnlyRequest(unsafe).has_value());

  unsafe = allowed;
  unsafe.kind = ExistingPositionMutationKind::kTightenStop;
  assert(!BuildBitunixManagementOnlyRequest(unsafe).has_value());

  unsafe = allowed;
  unsafe.position_id = "1984\"}";
  assert(!BuildBitunixManagementOnlyRequest(unsafe).has_value());

  unsafe = allowed;
  unsafe.position_id = "";
  assert(!BuildBitunixManagementOnlyRequest(unsafe).has_value());

  return 0;
}
