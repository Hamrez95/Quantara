#include "management_only_worker_core.h"

#include <iostream>
#include <string>

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
                                              bool stop,
                                              bool take_profit) {
  quantara::BitunixPendingOrder order{};
  order.order_id = std::move(id);
  order.position_id = std::move(position_id);
  order.symbol = "BTCUSDT";
  order.status = "NEW";
  order.reduce_only = true;
  if (stop) order.stop_loss_price = "60000";
  if (take_profit) order.take_profit_price = "70000";
  return order;
}

quantara::DurableReconciliationEvidence Durable(std::string id) {
  quantara::DurableReconciliationEvidence evidence{};
  evidence.position_id = std::move(id);
  evidence.symbol = "BTCUSDT";
  evidence.has_unambiguous_quantara_identity = true;
  evidence.has_conflicting_order_fill_or_history = false;
  evidence.has_durable_reconstruction = true;
  evidence.expected_take_profit_order_count = 1;
  return evidence;
}

bool ExternalPositionIsClassifiedFailClosed() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("manual-1"));
  truth.pending_orders.total = 0;

  quantara::WindowsManagementOnlyWorkerCore worker;
  const auto snapshot = worker.ReconcileFreshExchangeTruth(truth, {});
  return snapshot.has_value() &&
         snapshot->classification ==
             quantara::ExistingPositionClassification::kExternalUnmanaged &&
         snapshot->mode == quantara::ManagementOnlyRecoveryMode::kDisarmed &&
         !worker.CanManageExistingPositions() && !worker.CanOpenNewEntry();
}

bool VerifiedQuantaraPositionGetsManagementOnlyAuthority() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("sl-1", "p-1", true, false));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("tp-1", "p-1", false, true));
  truth.pending_orders.total = 2;

  quantara::WindowsManagementOnlyWorkerCore worker;
  const auto snapshot =
      worker.ReconcileFreshExchangeTruth(truth, {Durable("p-1")});
  return snapshot.has_value() &&
         snapshot->mode ==
             quantara::ManagementOnlyRecoveryMode::kManageExistingOnly &&
         worker.CanManageExistingPositions() && !worker.CanOpenNewEntry() &&
         snapshot->blocks_new_entries;
}

bool LifecycleBoundaryRevokesManagementAuthority() {
  quantara::BitunixExchangeTruthSnapshot truth{};
  truth.positions.push_back(Position("p-1"));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("sl-1", "p-1", true, false));
  truth.pending_orders.orders.push_back(
      ProtectionOrder("tp-1", "p-1", false, true));
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

  quantara::WindowsManagementOnlyWorkerCore worker;
  const auto snapshot = worker.ReconcileFreshExchangeTruth(
      truth, {Durable("missing-from-exchange")});
  return snapshot.has_value() &&
         snapshot->mode ==
             quantara::ManagementOnlyRecoveryMode::kReconciliationRequired &&
         snapshot->reason == "staleDurableEvidence" &&
         !worker.CanManageExistingPositions() && !worker.CanOpenNewEntry();
}

}  // namespace

int main() {
  if (!ExternalPositionIsClassifiedFailClosed() ||
      !VerifiedQuantaraPositionGetsManagementOnlyAuthority() ||
      !LifecycleBoundaryRevokesManagementAuthority() ||
      !StaleDurableEvidenceRequiresReconciliation()) {
    std::cerr << "management-only worker core test failed\n";
    return 1;
  }
  return 0;
}
