#include "bitunix_management_only_reconciliation.h"
#include "management_only_worker_core.h"

#include <iostream>
#include <string>
#include <vector>

namespace {

quantara::BitunixPendingPosition Position(std::string id,
                                         std::string symbol = "BTCUSDT",
                                         std::string quantity = "1.000") {
  quantara::BitunixPendingPosition position{};
  position.position_id = std::move(id);
  position.symbol = std::move(symbol);
  position.quantity = std::move(quantity);
  position.margin_mode = "ISOLATION";
  return position;
}

quantara::BitunixPendingTpSlOrder TpSlOrder(std::string id,
                                           std::string position_id,
                                           std::string symbol,
                                           std::string stop_quantity,
                                           std::string tp_quantity) {
  quantara::BitunixPendingTpSlOrder order{};
  order.order_id = std::move(id);
  order.position_id = std::move(position_id);
  order.symbol = std::move(symbol);
  if (!stop_quantity.empty()) {
    order.stop_loss_price = "60000";
    order.stop_loss_quantity = std::move(stop_quantity);
  }
  if (!tp_quantity.empty()) {
    order.take_profit_price = "70000";
    order.take_profit_quantity = std::move(tp_quantity);
  }
  return order;
}

quantara::DurableReconciliationEvidence Durable(
    std::string id, std::string symbol = "BTCUSDT",
    std::size_t expected_take_profits = 1) {
  quantara::DurableReconciliationEvidence evidence{};
  evidence.position_id = std::move(id);
  evidence.symbol = std::move(symbol);
  evidence.has_unambiguous_quantara_identity = true;
  evidence.has_conflicting_order_fill_or_history = false;
  evidence.has_durable_reconstruction = true;
  evidence.expected_take_profit_order_count = expected_take_profits;
  return evidence;
}

quantara::BitunixExchangeTruthSnapshot FullyProtectedTruth() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.total = 0;
  // Numerically equal decimal spellings must compare exactly without float.
  truth.pending_tpsl_orders.push_back(
      TpSlOrder("protect-1", "p-1", "BTCUSDT", "1", "1.0000"));
  return truth;
}

bool VerifiedPositionGrantsManagementOnly() {
  auto truth = FullyProtectedTruth();
  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1")}, coordinator);
  return snapshot.mode ==
             quantara::ManagementOnlyRecoveryMode::kManageExistingOnly &&
         coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry() && snapshot.blocks_new_entries;
}

bool SplitTakeProfitCoverageGrantsManagementOnly() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1", "BTCUSDT", "1.0"));
  truth.pending_orders.total = 0;
  truth.pending_tpsl_orders.push_back(
      TpSlOrder("sl-tp-1", "p-1", "BTCUSDT", "1.000", "0.40"));
  truth.pending_tpsl_orders.push_back(
      TpSlOrder("tp-2", "p-1", "BTCUSDT", "", "0.600"));

  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1", "BTCUSDT", 2)}, coordinator);
  return snapshot.mode ==
             quantara::ManagementOnlyRecoveryMode::kManageExistingOnly &&
         coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry();
}

bool PartialStopCoverageNeverGrantsManagement() {
  auto truth = FullyProtectedTruth();
  truth.pending_tpsl_orders[0].stop_loss_quantity = "0.999";
  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1")}, coordinator);
  return snapshot.mode !=
             quantara::ManagementOnlyRecoveryMode::kManageExistingOnly &&
         !coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry();
}

bool PartialTakeProfitCoverageNeverGrantsManagement() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.total = 0;
  truth.pending_tpsl_orders.push_back(
      TpSlOrder("sl-tp-1", "p-1", "BTCUSDT", "1", "0.4"));
  truth.pending_tpsl_orders.push_back(
      TpSlOrder("tp-2", "p-1", "BTCUSDT", "", "0.5"));
  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1", "BTCUSDT", 2)}, coordinator);
  return snapshot.mode !=
             quantara::ManagementOnlyRecoveryMode::kManageExistingOnly &&
         !coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry();
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
  auto truth = FullyProtectedTruth();
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

bool MissingTakeProfitNeverGrantsManagement() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.total = 0;
  truth.pending_tpsl_orders.push_back(
      TpSlOrder("sl-1", "p-1", "BTCUSDT", "1", ""));
  quantara::ManagementOnlyRecoveryCoordinator coordinator;
  const auto snapshot = quantara::ReconcileBitunixManagementOnly(
      truth, {Durable("p-1")}, coordinator);
  return snapshot.mode !=
             quantara::ManagementOnlyRecoveryMode::kManageExistingOnly &&
         !coordinator.CanManageExistingPositions() &&
         !coordinator.CanOpenNewEntry();
}

}  // namespace

int main() {
  if (!VerifiedPositionGrantsManagementOnly() ||
      !SplitTakeProfitCoverageGrantsManagementOnly() ||
      !PartialStopCoverageNeverGrantsManagement() ||
      !PartialTakeProfitCoverageNeverGrantsManagement() ||
      !ExchangePositionWithoutDurableEvidenceIsExternal() ||
      !WorkerCorePreservesExternalClassification() ||
      !WorkerLifecycleBoundaryRevokesManagementAuthority() ||
      !StaleDurableEvidenceRequiresReconciliation() ||
      !DuplicateDurableEvidenceRequiresReconciliation() ||
      !MissingTakeProfitNeverGrantsManagement()) {
    std::cerr << "bitunix management-only reconciliation test failed\n";
    return 1;
  }
  return 0;
}
