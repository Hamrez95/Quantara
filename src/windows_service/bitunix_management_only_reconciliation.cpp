#include "bitunix_management_only_reconciliation.h"

#include <cstddef>

namespace quantara {

ManagementOnlyRecoverySnapshot ReconcileBitunixManagementOnly(
    const BitunixExchangeTruthSnapshot& exchange_truth,
    const std::vector<DurableReconciliationEvidence>& durable_evidence,
    ManagementOnlyRecoveryCoordinator& coordinator) noexcept {
  coordinator.RequireFreshReconciliation("freshExchangeTruthRequired");

  std::vector<ExistingExchangePositionFacts> facts;
  facts.reserve(exchange_truth.positions.size());
  std::vector<bool> evidence_used(durable_evidence.size(), false);

  for (const auto& position : exchange_truth.positions) {
    const DurableReconciliationEvidence* matched = nullptr;
    std::size_t matched_index = 0;
    for (std::size_t i = 0; i < durable_evidence.size(); ++i) {
      if (durable_evidence[i].position_id == position.position_id &&
          durable_evidence[i].symbol == position.symbol) {
        if (matched != nullptr) {
          coordinator.RequireFreshReconciliation("duplicateDurableEvidence");
          return coordinator.snapshot();
        }
        matched = &durable_evidence[i];
        matched_index = i;
      }
    }

    if (matched == nullptr) {
      ExistingExchangePositionFacts external{};
      external.position_id = position.position_id;
      external.symbol = position.symbol;
      external.isolated_margin = position.margin_mode == "ISOLATION";
      external.has_conflicting_order_fill_or_history = true;
      facts.push_back(external);
      continue;
    }

    evidence_used[matched_index] = true;
    const auto current = ApplyCurrentExchangeProtectionEvidence(
        position, *matched, exchange_truth.pending_orders,
        exchange_truth.pending_tpsl_orders);
    if (!current.has_value()) {
      coordinator.RequireFreshReconciliation("exchangeEvidenceJoinFailed");
      return coordinator.snapshot();
    }
    const auto joined = BuildExistingExchangePositionFacts(position, *current);
    if (!joined.has_value()) {
      coordinator.RequireFreshReconciliation("exchangeEvidenceJoinFailed");
      return coordinator.snapshot();
    }
    facts.push_back(*joined);
  }

  for (std::size_t i = 0; i < evidence_used.size(); ++i) {
    if (!evidence_used[i]) {
      coordinator.RequireFreshReconciliation("staleDurableEvidence");
      return coordinator.snapshot();
    }
  }

  return coordinator.Reconcile(facts);
}

}  // namespace quantara
