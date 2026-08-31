#include "bitunix_management_only_reconciliation.h"
#include "bitunix_reconciliation_facts_adapter.h"
#include "management_only_worker_core.h"

#include <cmath>
#include <iostream>
#include <string>
#include <vector>

namespace {

quantara::BitunixPendingPosition Position(std::string id,
                                         std::string symbol = "BTCUSDT",
                                         std::string quantity = "1.000",
                                         std::string side = "LONG") {
  quantara::BitunixPendingPosition position{};
  position.position_id = std::move(id);
  position.symbol = std::move(symbol);
  position.quantity = std::move(quantity);
  position.margin_mode = "ISOLATION";
  position.side = std::move(side);
  return position;
}

quantara::BitunixPendingTpSlOrder TpSlOrder(std::string id,
                                           std::string position_id,
                                           std::string symbol,
                                           std::string stop_quantity,
                                           std::string tp_quantity,
                                           std::string stop_type = "MARK_PRICE") {
  quantara::BitunixPendingTpSlOrder order{};
  order.order_id = std::move(id);
  order.position_id = std::move(position_id);
  order.symbol = std::move(symbol);
  if (!stop_quantity.empty()) {
    order.stop_loss_price = "60000";
    order.stop_loss_quantity = std::move(stop_quantity);
    order.stop_loss_stop_type = std::move(stop_type);
  }
  if (!tp_quantity.empty()) {
    order.take_profit_price = "70000";
    order.take_profit_quantity = std::move(tp_quantity);
    order.take_profit_stop_type = "MARK_PRICE";
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

bool CurrentStopFactsComeOnlyFromFreshTruth() {
  const auto position = Position("p-1", "BTCUSDT", "1", "SHORT");
  auto durable = Durable("p-1");
  // Stale/caller-supplied values must be overwritten by current exchange truth.
  durable.current_stop_price = 123.0;
  durable.current_stop_trigger_type = "LAST_PRICE";
  quantara::BitunixPendingOrdersSnapshot pending_orders{};
  pending_orders.total = 0;
  auto stop = TpSlOrder("protect-1", "p-1", "BTCUSDT", "1.000", "1");
  stop.stop_loss_price = "70123.5";
  stop.stop_loss_stop_type = "MARK_PRICE";

  const auto joined = quantara::ApplyCurrentExchangeProtectionEvidence(
      position, durable, pending_orders, {stop});
  if (!joined.has_value() || !joined->has_complete_exchange_stop ||
      std::abs(joined->current_stop_price - 70123.5) > 1e-9 ||
      joined->current_stop_trigger_type != "MARK_PRICE") {
    return false;
  }
  const auto facts =
      quantara::BuildExistingExchangePositionFacts(position, *joined);
  return facts.has_value() &&
         facts->side == quantara::ExistingPositionSide::kShort &&
         std::abs(facts->current_stop_price - 70123.5) < 1e-9 &&
         facts->current_stop_trigger_type == "MARK_PRICE";
}

bool InvalidStopTriggerFailsClosed() {
  const auto position = Position("p-1");
  auto durable = Durable("p-1");
  quantara::BitunixPendingOrdersSnapshot pending_orders{};
  pending_orders.total = 0;
  auto stop = TpSlOrder("protect-1", "p-1", "BTCUSDT", "1", "1");
  stop.stop_loss_stop_type = "INDEX_PRICE";
  const auto joined = quantara::ApplyCurrentExchangeProtectionEvidence(
      position, durable, pending_orders, {stop});
  return joined.has_value() && !joined->has_complete_exchange_stop &&
         joined->current_stop_price == 0.0 &&
         joined->current_stop_trigger_type.empty() &&
         joined->has_conflicting_order_fill_or_history;
}

bool InvalidStopPriceFailsClosed() {
  const auto position = Position("p-1");
  auto durable = Durable("p-1");
  quantara::BitunixPendingOrdersSnapshot pending_orders{};
  pending_orders.total = 0;
  auto stop = TpSlOrder("protect-1", "p-1", "BTCUSDT", "1", "1");
  stop.stop_loss_price = "nan";
  const auto joined = quantara::ApplyCurrentExchangeProtectionEvidence(
      position, durable, pending_orders, {stop});
  return joined.has_value() && !joined->has_complete_exchange_stop &&
         joined->current_stop_price == 0.0 &&
         joined->current_stop_trigger_type.empty() &&
         joined->has_conflicting_order_fill_or_history;
}

bool UnknownSideNeverInvented() {
  const auto position = Position("p-1", "BTCUSDT", "1", "BOTH");
  auto durable = Durable("p-1");
  quantara::BitunixPendingOrdersSnapshot pending_orders{};
  pending_orders.total = 0;
  const auto stop = TpSlOrder("protect-1", "p-1", "BTCUSDT", "1", "1");
  const auto joined = quantara::ApplyCurrentExchangeProtectionEvidence(
      position, durable, pending_orders, {stop});
  if (!joined.has_value()) return false;
  const auto facts =
      quantara::BuildExistingExchangePositionFacts(position, *joined);
  return facts.has_value() &&
         facts->side == quantara::ExistingPositionSide::kUnknown;
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
      !CurrentStopFactsComeOnlyFromFreshTruth() ||
      !InvalidStopTriggerFailsClosed() || !InvalidStopPriceFailsClosed() ||
      !UnknownSideNeverInvented() ||
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
