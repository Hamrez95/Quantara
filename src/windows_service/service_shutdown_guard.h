#pragma once

#include "ipc_response_protocol.h"

namespace quantara {

// SCM stop/shutdown is an authority boundary. The published service state must
// be revoked immediately and any exchange reconciliation already in flight
// must be prevented from restoring management authority after that boundary.
constexpr ServiceSafetyState ServiceSafetyStateForStopBoundary() noexcept {
  return ServiceSafetyState::kInterrupted;
}

constexpr bool ShouldPublishReconciliationResult(
    bool stop_requested, bool newer_lifecycle_boundary_arrived) noexcept {
  return !stop_requested && !newer_lifecycle_boundary_arrived;
}

// A successful recovery classification is not itself executable authority.
// Until the running service owns a wired management-only mutation executor,
// advertising manageExistingOnly would falsely claim that verified positions
// can actually be protected/closed. Keep the public state fail-closed while the
// executor attachment is absent. Other safety states are preserved verbatim.
constexpr ServiceSafetyState ServiceSafetyStateForRuntimeCapability(
    ServiceSafetyState reconciled_state,
    bool management_executor_attached) noexcept {
  if (reconciled_state == ServiceSafetyState::kManageExistingOnly &&
      !management_executor_attached) {
    return ServiceSafetyState::kReconciliationRequired;
  }
  return reconciled_state;
}

}  // namespace quantara
