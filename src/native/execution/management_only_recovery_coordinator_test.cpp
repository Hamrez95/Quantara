#include "management_only_recovery_coordinator.h"

#include <iostream>
#include <string_view>

namespace {

using quantara::ExistingExchangePositionFacts;
using quantara::ExistingPositionClassification;
using quantara::ExistingPositionManagementAuthority;
using quantara::ManagementOnlyRecoveryCoordinator;
using quantara::ManagementOnlyRecoveryMode;
using quantara::ManagementOnlyRecoverySnapshot;
using quantara::RecoveryLifecycleBoundary;

ExistingExchangePositionFacts Verified(bool managed = false) {
  return {.position_id = "position-1",
          .symbol = "BTCUSDT",
          .isolated_margin = true,
          .has_unambiguous_quantara_identity = true,
          .has_complete_exchange_stop = true,
          .has_complete_exchange_take_profit_ladder = true,
          .has_conflicting_order_fill_or_history = false,
          .has_durable_reconstruction = true,
          .is_already_managed = managed};
}

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

bool ExpectSnapshot(const ManagementOnlyRecoverySnapshot& snapshot,
                    ManagementOnlyRecoveryMode mode,
                    ExistingPositionClassification classification,
                    ExistingPositionManagementAuthority authority,
                    std::string_view reason, const char* message) {
  return Expect(snapshot.mode == mode &&
                    snapshot.classification == classification &&
                    snapshot.authority == authority &&
                    snapshot.blocks_new_entries && snapshot.reason == reason,
                message);
}

}  // namespace

int main() {
  bool ok = true;

  ManagementOnlyRecoveryCoordinator coordinator;
  ok &= ExpectSnapshot(coordinator.snapshot(), ManagementOnlyRecoveryMode::kDisarmed,
                       ExistingPositionClassification::kManaged,
                       ExistingPositionManagementAuthority::kNone,
                       "startupDisarmed",
                       "Startup must be disarmed without entry authority.");
  ok &= Expect(!coordinator.CanManageExistingPositions(),
               "Startup must not manage positions before reconciliation.");
  ok &= Expect(!coordinator.CanOpenNewEntry(),
               "Management-only coordinator must never open a new entry.");

  const auto orphan = coordinator.Reconcile({Verified(false)});
  ok &= ExpectSnapshot(orphan, ManagementOnlyRecoveryMode::kManageExistingOnly,
                       ExistingPositionClassification::kRecoverableOrphan,
                       ExistingPositionManagementAuthority::kManageExistingOnly,
                       "allOrphansRecoverable",
                       "Verified orphan must become management-only.");
  ok &= Expect(coordinator.CanManageExistingPositions(),
               "Verified orphan should allow existing-position management.");
  ok &= Expect(!coordinator.CanOpenNewEntry(),
               "Orphan recovery must not grant entry authority.");

  const auto orphan_repeat = coordinator.Reconcile({Verified(false)});
  ok &= ExpectSnapshot(orphan_repeat,
                       ManagementOnlyRecoveryMode::kManageExistingOnly,
                       ExistingPositionClassification::kRecoverableOrphan,
                       ExistingPositionManagementAuthority::kManageExistingOnly,
                       "allOrphansRecoverable",
                       "Duplicate reconciliation must be idempotent.");

  coordinator.MarkLifecycleBoundary(RecoveryLifecycleBoundary::kNetworkRestored);
  ok &= ExpectSnapshot(coordinator.snapshot(),
                       ManagementOnlyRecoveryMode::kReconciliationRequired,
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "networkRestoreRequiresReconciliation",
                       "Network restoration must strip management authority.");
  ok &= Expect(!coordinator.CanManageExistingPositions(),
               "Lifecycle boundary must strip management authority.");

  coordinator.MarkLifecycleBoundary(RecoveryLifecycleBoundary::kNetworkRestored);
  ok &= ExpectSnapshot(coordinator.snapshot(),
                       ManagementOnlyRecoveryMode::kReconciliationRequired,
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "networkRestoreRequiresReconciliation",
                       "Duplicate lifecycle boundary must be idempotent.");

  const auto managed = coordinator.Reconcile({Verified(true)});
  ok &= ExpectSnapshot(managed, ManagementOnlyRecoveryMode::kManageExistingOnly,
                       ExistingPositionClassification::kManaged,
                       ExistingPositionManagementAuthority::kManageExistingOnly,
                       "allManagedVerified",
                       "Verified managed position must remain management-only.");

  coordinator.MarkLifecycleBoundary(RecoveryLifecycleBoundary::kPowerResume);
  ok &= ExpectSnapshot(coordinator.snapshot(),
                       ManagementOnlyRecoveryMode::kReconciliationRequired,
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "powerResumeRequiresReconciliation",
                       "Power resume must require fresh reconciliation.");

  const auto empty = coordinator.Reconcile({});
  ok &= ExpectSnapshot(empty, ManagementOnlyRecoveryMode::kDisarmed,
                       ExistingPositionClassification::kManaged,
                       ExistingPositionManagementAuthority::kNone,
                       "noOpenExchangePositions",
                       "Empty exchange truth must remain disarmed.");

  auto external = Verified();
  external.has_unambiguous_quantara_identity = false;
  const auto external_result = coordinator.Reconcile({external});
  ok &= ExpectSnapshot(external_result, ManagementOnlyRecoveryMode::kDisarmed,
                       ExistingPositionClassification::kExternalUnmanaged,
                       ExistingPositionManagementAuthority::kNone,
                       "quantaraOwnershipUnproven",
                       "External position must remain unmanaged.");

  auto cross_margin = Verified();
  cross_margin.isolated_margin = false;
  const auto cross_result = coordinator.Reconcile({cross_margin});
  ok &= ExpectSnapshot(cross_result, ManagementOnlyRecoveryMode::kDisarmed,
                       ExistingPositionClassification::kExternalUnmanaged,
                       ExistingPositionManagementAuthority::kNone,
                       "crossOrUnknownMargin",
                       "Cross-margin position must remain unmanaged.");

  auto missing_protection = Verified();
  missing_protection.has_complete_exchange_stop = false;
  const auto missing_protection_result =
      coordinator.Reconcile({missing_protection});
  ok &= ExpectSnapshot(
      missing_protection_result,
      ManagementOnlyRecoveryMode::kReconciliationRequired,
      ExistingPositionClassification::kAmbiguous,
      ExistingPositionManagementAuthority::kReconciliationOnly,
      "exchangeNativeProtectionIncomplete",
      "Missing exchange protection must require reconciliation.");

  auto history_conflict = Verified();
  history_conflict.has_conflicting_order_fill_or_history = true;
  const auto history_result = coordinator.Reconcile({history_conflict});
  ok &= ExpectSnapshot(history_result,
                       ManagementOnlyRecoveryMode::kReconciliationRequired,
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "exchangeHistoryConflicts",
                       "Conflicting exchange history must require reconciliation.");

  auto reconstruction_missing = Verified();
  reconstruction_missing.has_durable_reconstruction = false;
  const auto reconstruction_result = coordinator.Reconcile({reconstruction_missing});
  ok &= ExpectSnapshot(
      reconstruction_result, ManagementOnlyRecoveryMode::kReconciliationRequired,
      ExistingPositionClassification::kAmbiguous,
      ExistingPositionManagementAuthority::kReconciliationOnly,
      "durableReconstructionUnavailable",
      "Missing durable reconstruction must require reconciliation.");

  for (const auto boundary : {RecoveryLifecycleBoundary::kRestart,
                              RecoveryLifecycleBoundary::kUpdate,
                              RecoveryLifecycleBoundary::kRollback}) {
    coordinator.Reconcile({Verified(true)});
    coordinator.MarkLifecycleBoundary(boundary);
    ok &= Expect(coordinator.snapshot().mode ==
                     ManagementOnlyRecoveryMode::kReconciliationRequired &&
                     !coordinator.CanManageExistingPositions() &&
                     !coordinator.CanOpenNewEntry(),
                 "Restart/update/rollback must strip authority fail-closed.");
  }

  return ok ? 0 : 1;
}
