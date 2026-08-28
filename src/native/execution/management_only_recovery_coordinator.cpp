#include "management_only_recovery_coordinator.h"

namespace quantara {
namespace {

constexpr ManagementOnlyRecoverySnapshot Disarmed(std::string_view reason) {
  return {ManagementOnlyRecoveryMode::kDisarmed,
          ExistingPositionClassification::kAmbiguous,
          ExistingPositionManagementAuthority::kNone, true, reason};
}

constexpr ManagementOnlyRecoverySnapshot ReconciliationRequired(
    std::string_view reason) {
  return {ManagementOnlyRecoveryMode::kReconciliationRequired,
          ExistingPositionClassification::kAmbiguous,
          ExistingPositionManagementAuthority::kReconciliationOnly, true,
          reason};
}

constexpr std::string_view BoundaryReason(
    RecoveryLifecycleBoundary boundary) noexcept {
  switch (boundary) {
    case RecoveryLifecycleBoundary::kRestart:
      return "restartRequiresReconciliation";
    case RecoveryLifecycleBoundary::kPowerResume:
      return "powerResumeRequiresReconciliation";
    case RecoveryLifecycleBoundary::kNetworkRestored:
      return "networkRestoreRequiresReconciliation";
    case RecoveryLifecycleBoundary::kUpdate:
      return "updateRequiresReconciliation";
    case RecoveryLifecycleBoundary::kRollback:
      return "rollbackRequiresReconciliation";
  }
  return "lifecycleBoundaryRequiresReconciliation";
}

}  // namespace

ManagementOnlyRecoveryCoordinator::ManagementOnlyRecoveryCoordinator() noexcept
    : snapshot_(Disarmed("startupDisarmed")) {}

const ManagementOnlyRecoverySnapshot&
ManagementOnlyRecoveryCoordinator::snapshot() const noexcept {
  return snapshot_;
}

void ManagementOnlyRecoveryCoordinator::MarkLifecycleBoundary(
    RecoveryLifecycleBoundary boundary) noexcept {
  snapshot_ = ReconciliationRequired(BoundaryReason(boundary));
}

void ManagementOnlyRecoveryCoordinator::RequireFreshReconciliation(
    std::string_view reason) noexcept {
  snapshot_ = ReconciliationRequired(reason);
}

ManagementOnlyRecoverySnapshot ManagementOnlyRecoveryCoordinator::Reconcile(
    const std::vector<ExistingExchangePositionFacts>& positions) noexcept {
  const auto decision = EvaluateExistingPortfolio(positions);
  if (decision.authority ==
      ExistingPositionManagementAuthority::kManageExistingOnly) {
    snapshot_ = {ManagementOnlyRecoveryMode::kManageExistingOnly,
                 decision.classification, decision.authority, true,
                 decision.reason};
  } else if (decision.authority ==
             ExistingPositionManagementAuthority::kReconciliationOnly) {
    snapshot_ = {ManagementOnlyRecoveryMode::kReconciliationRequired,
                 decision.classification, decision.authority, true,
                 decision.reason};
  } else {
    snapshot_ = {ManagementOnlyRecoveryMode::kDisarmed,
                 decision.classification, decision.authority, true,
                 decision.reason};
  }
  return snapshot_;
}

bool ManagementOnlyRecoveryCoordinator::CanManageExistingPositions()
    const noexcept {
  return snapshot_.mode == ManagementOnlyRecoveryMode::kManageExistingOnly &&
         snapshot_.authority ==
             ExistingPositionManagementAuthority::kManageExistingOnly;
}

bool ManagementOnlyRecoveryCoordinator::CanOpenNewEntry() const noexcept {
  return false;
}

}  // namespace quantara
