#pragma once

#include "../native/execution/existing_position_management_policy.h"

#include <optional>
#include <string>

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
[[nodiscard]] std::optional<BitunixManagementOnlyHttpRequest>
BuildBitunixManagementOnlyRequest(
    const ExistingPositionMutationRequest& request) noexcept;

}  // namespace quantara
