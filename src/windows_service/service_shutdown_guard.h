#pragma once

#include "ipc_response_protocol.h"

namespace quantara {

// SCM stop/shutdown is an authority boundary. The published service state must
// be revoked immediately and any exchange reconciliation already in flight
// must be prevented from restoring management authority after that boundary.
constexpr ServiceSafetyState ServiceSafetyStateForStopBoundary() noexcept {
  return ServiceSafetyState::kReconciliationRequired;
}

constexpr bool ShouldPublishReconciliationResult(
    bool stop_requested, bool newer_lifecycle_boundary_arrived) noexcept {
  return !stop_requested && !newer_lifecycle_boundary_arrived;
}

}  // namespace quantara
