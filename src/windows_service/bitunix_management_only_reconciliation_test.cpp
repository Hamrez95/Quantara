#include "bitunix_management_only_reconciliation.h"
#include "management_only_worker_core.h"

#include <iostream>
#include <string>
#include <vector>

namespace {

quantara::BitunixPendingPosition Position(std::string id,
                                         std::string symbol = "BTCUSDT") {
  quantara::BitunixPendingPosition position{};
  position.position_id = std::move(id);
  position.symbol = std::move(symbol);
  position.margin_mode = "ISOLATION";
  return position;
}

quantara::BitunixPendingOrder ProtectionOrder(std::string id,
                                              std::string position_id,
                                              std::string symbol,
                                              bool stop,
                                              bool take_profit) {
  quantara::BitunixPendingOrder order{};
  order.order_id = std::move(id);
  order.position_id = std::move(position_id);
  order.symbol = std::move(symbol);
  order.status = "NEW";
  order.reduce_only = true;
  if (stop) order.stop_loss_price = "60000";
  if (take_profit) order.take_profit_price = "70000";
  return order;
}

quantara::DurableReconciliationEvidence Durable(std::string id,
                                                std::string symbol = "BTCUSDT") {
  quantara::DurableReconciliationEvidence evidence{};
  evidence.position_id = std::move(id);
  evidence.symbol = std::move(symbol);
  evidence.has_unambiguous_quantara_identity = true;
  evidence.has_conflicting_order_fill_or_history = false;
  evidence.has_durable_reconstruction = true;
  evidence.expected_take_profit_order_count = 1;
  return evidence;
}

bool VerifiedPositionGrantsManagementOnly() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("sl-1", "p-1", "BTCUSDT", true, false));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("tp-1", "p-1", "BTCUSDT", false, true));
  truth.pending_orders.total = 2;

  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1")}, coordinator);
  return snapshot.mode ==
             quantara::ManagementOnlyRecoveryMode::kManageExistingOnly &&
         coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry() && snapshot.blocks_new_entries;
}

bool ExchangePositionWithoutDurableEvidenceIsExternal() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("external-1"));
  truth.pending_orders.total = 0;

  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot =
      quantara::ReconcileBitunixManagementOnly(truth, {}, coordinator);
  return snapshot.mode == quantara::ManagementOnlyRecoveryMode::kDisarmed &&
         snapshot.classification ==
             quantara::ExistingPositionClassification::kExternalUnmanaged &&
         !coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry();
}

bool WorkerCorePreservesExternalClassification() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("manual-1"));
  truth.pending_orders.total = 0;

  quantara::WindowsManagementOnlyWorkerCore worker;
  const auto snapshot = worker.ReconcileFreshExchangeTruth(truth, {});
  return snapshot.has_value() &&
         snapshot->mode == quantara::ManagementOnlyRecoveryMode::kDisarmed &&
         snapshot->classification ==
             quantara::ExistingPositionClassification::kExternalUnmanaged &&
         !worker.CanManageExistingPositions() && !worker.CanOpenNewEntry();
}

bool WorkerLifecycleBoundaryRevokesManagementAuthority() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("sl-1", "p-1", "BTCUSDT", true, false));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("tp-1", "p-1", "BTCUSDT", false, true));
  truth.pending_orders.total = 2;

  quantara::WindowsManagementOnlyWorkerCore worker;
  const auto reconciled =
      worker.ReconcileFreshExchangeTruth(truth, {Durable("p-1")});
  if (!reconciled.has_value() || !worker.CanManageExistingPositions()) {
    return false;
  }
  worker.MarkLifecycleBoundary(
      quantara::RecoveryLifecycleBoundary::kNetworkRestored);
  return worker.snapshot().mode ==
             quantara::ManagementOnlyRecoveryMode::kReconciliationRequired &&
         !worker.CanManageExistingPositions() && !worker.CanOpenNewEntry();
}

bool StaleDurableEvidenceRequiresReconciliation() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.pending_orders.total = 0;
  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("missing-from-exchange")}, coordinator);
  return snapshot.mode ==
             quantara::ManagementOnlyRecoveryMode::kReconciliationRequired &&
         snapshot.reason == "staleDurableEvidence" &&
         !coordinator.CanManageExistingPositions();
}

bool DuplicateDurableEvidenceRequiresReconciliation() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.total = 0;
  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1"), Durable("p-1")}, coordinator);
  return snapshot.mode ==
             quantara::ManagementOnlyRecoveryMode::kReconciliationRequired &&
         snapshot.reason == "duplicateDurableEvidence";
}

bool IncompleteProtectionNeverGrantsManagement() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("sl-1", "p-1", "BTCUSDT", true, false));
  truth.pending_orders.total = 1;
  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1")}, coordinator);
  return snapshot.mode ==
             quantara::ManagementOnlyRecoveryMode::kReconciliationRequired &&
         !coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry();
}

}  // namespace

int main() {
  if (!VerifiedPositionGrantsManagementOnly() ||
      !ExchangePositionWithoutDurableEvidenceIsExternal() ||
      !WorkerCorePreservesExternalClassification() ||
      !WorkerLifecycleBoundaryRevokesManagementAuthority() ||
      !StaleDurableEvidenceRequiresReconciliation() ||
      !DuplicateDurableEvidenceRequiresReconciliation() ||
      !IncompleteProtectionNeverGrantsManagement()) {
    std::cerr << "bitunix management-only reconciliation test failed\n";
    return 1;
  }
  return 0;
}
