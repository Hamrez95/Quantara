#include "management_only_recovery_coordinator.h"
#include "../../windows_service/management_only_worker_core.h"

#include <iostream>
#include <string_view>

namespace {

using quantara::BitunixExchangeTruthSnapshot;
using quantara::BitunixPendingOrder;
using quantara::BitunixPendingOrdersSnapshot;
using quantara::BitunixPendingPosition;
using quantara::DurableReconciliationEvidence;
using quantara::ExistingExchangePositionFacts;
using quantara::ExistingPositionClassification;
using quantara::ExistingPositionManagementAuthority;
using quantara::ManagementOnlyRecoveryCoordinator;
using quantara::ManagementOnlyRecoveryMode;
using quantara::ManagementOnlyRecoverySnapshot;
using quantara::RecoveryLifecycleBoundary;
using quantara::WindowsManagementOnlyWorkerCore;

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

BitunixPendingPosition ParsedPosition(std::string id = "position-1",
                                      std::string symbol = "BTCUSDT") {
  BitunixPendingPosition position{};
  position.position_id = std::move(id);
  position.symbol = std::move(symbol);
  position.quantity = "0.001";
  position.side = "LONG";
  position.margin_mode = "ISOLATION";
  position.position_mode = "ONE_WAY";
  position.leverage = 5;
  return position;
}

BitunixExchangeTruthSnapshot ProtectedTruth() {
  BitunixPendingOrder protection{};
  protection.order_id = "protection-1";
  protection.position_id = "position-1";
  protection.symbol = "BTCUSDT";
  protection.status = "NEW";
  protection.reduce_only = true;
  protection.take_profit_price = "70000";
  protection.stop_loss_price = "60000";

  BitunixPendingOrdersSnapshot pending{};
  pending.orders.push_back(std::move(protection));
  pending.total = 1;
  return {.positions = {ParsedPosition()}, .pending_orders = std::move(pending)};
}

DurableReconciliationEvidence DurableEvidence(
    std::string id = "position-1", std::string symbol = "BTCUSDT") {
  DurableReconciliationEvidence evidence{};
  evidence.position_id = std::move(id);
  evidence.symbol = std::move(symbol);
  evidence.has_unambiguous_quantara_identity = true;
  // These stale/pre-populated flags must be ignored by the Windows worker. The
  // worker recomputes current protection only from the pending-order snapshot.
  evidence.has_complete_exchange_stop = true;
  evidence.has_complete_exchange_take_profit_ladder = true;
  evidence.has_conflicting_order_fill_or_history = false;
  evidence.has_durable_reconstruction = true;
  evidence.expected_take_profit_order_count = 1;
  return evidence;
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
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kNone,
                       "startupDisarmed",
                       "Startup must be disarmed without exchange-truth classification.");
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

  coordinator.RequireFreshReconciliation("freshExchangeTruthRequired");
  ok &= ExpectSnapshot(coordinator.snapshot(),
                       ManagementOnlyRecoveryMode::kReconciliationRequired,
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "freshExchangeTruthRequired",
                       "A fresh exchange-truth cycle must revoke prior authority.");
  ok &= Expect(!coordinator.CanManageExistingPositions(),
               "Fresh reconciliation must revoke management authority before validation.");

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
    const auto restored = coordinator.Reconcile({Verified(true)});
    ok &= Expect(
        restored.mode == ManagementOnlyRecoveryMode::kManageExistingOnly &&
            coordinator.CanManageExistingPositions(),
        "Lifecycle-boundary test setup must begin from management-only state.");
    coordinator.MarkLifecycleBoundary(boundary);
    ok &= Expect(coordinator.snapshot().mode ==
                     ManagementOnlyRecoveryMode::kReconciliationRequired &&
                     !coordinator.CanManageExistingPositions() &&
                     !coordinator.CanOpenNewEntry(),
                 "Restart/update/rollback must strip authority fail-closed.");
  }

  WindowsManagementOnlyWorkerCore worker;
  const auto worker_reconciled = worker.ReconcileFreshExchangeTruth(
      ProtectedTruth(), {DurableEvidence()});
  ok &= Expect(worker_reconciled.has_value() &&
                   worker.CanManageExistingPositions() &&
                   !worker.CanOpenNewEntry(),
               "Windows worker may manage only a fully verified existing position.");

  const auto missing_evidence = worker.ReconcileFreshExchangeTruth(
      ProtectedTruth(), {});
  ok &= Expect(!missing_evidence.has_value() &&
                   !worker.CanManageExistingPositions() &&
                   worker.snapshot().mode ==
                       ManagementOnlyRecoveryMode::kReconciliationRequired,
               "Missing durable evidence must revoke prior management authority.");

  const auto duplicate_evidence = worker.ReconcileFreshExchangeTruth(
      ProtectedTruth(), {DurableEvidence(), DurableEvidence()});
  ok &= Expect(!duplicate_evidence.has_value() &&
                   !worker.CanManageExistingPositions(),
               "Duplicate durable evidence must fail closed.");

  auto ambiguous = DurableEvidence();
  ambiguous.has_unambiguous_quantara_identity = false;
  const auto ambiguous_result = worker.ReconcileFreshExchangeTruth(
      ProtectedTruth(), {ambiguous});
  ok &= Expect(ambiguous_result.has_value() &&
                   ambiguous_result->classification ==
                       ExistingPositionClassification::kExternalUnmanaged &&
                   !worker.CanManageExistingPositions(),
               "Ambiguous ownership must remain unmanaged in the Windows worker.");

  auto no_orders = ProtectedTruth();
  no_orders.pending_orders.orders.clear();
  no_orders.pending_orders.total = 0;
  const auto stale_flags_ignored = worker.ReconcileFreshExchangeTruth(
      no_orders, {DurableEvidence()});
  ok &= Expect(stale_flags_ignored.has_value() &&
                   stale_flags_ignored->classification ==
                       ExistingPositionClassification::kAmbiguous &&
                   !worker.CanManageExistingPositions(),
               "Pre-populated durable protection flags must not replace current exchange order truth.");

  auto unknown_ladder = DurableEvidence();
  unknown_ladder.expected_take_profit_order_count = 0;
  const auto unknown_ladder_result = worker.ReconcileFreshExchangeTruth(
      ProtectedTruth(), {unknown_ladder});
  ok &= Expect(unknown_ladder_result.has_value() &&
                   unknown_ladder_result->classification ==
                       ExistingPositionClassification::kAmbiguous &&
                   !worker.CanManageExistingPositions(),
               "Unknown durable TP ladder size must remain reconciliation-only.");

  worker.MarkLifecycleBoundary(RecoveryLifecycleBoundary::kUpdate);
  ok &= Expect(!worker.CanManageExistingPositions() &&
                   !worker.CanOpenNewEntry() &&
                   worker.snapshot().mode ==
                       ManagementOnlyRecoveryMode::kReconciliationRequired,
               "Windows update boundary must strip management authority.");

  return ok ? 0 : 1;
}
