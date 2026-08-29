#pragma once

#include "bitunix_exchange_truth_reader.h"
#include "bitunix_reconciliation_facts_adapter.h"
#include "../native/execution/management_only_recovery_coordinator.h"

#include <optional>
#include <vector>

namespace quantara {

// Windows-owned orchestration boundary for management-only recovery. It never
// submits orders and never grants new-entry authority. Every fresh exchange
// reconciliation strips prior authority before validating the complete join.
class WindowsManagementOnlyWorkerCore final {
 public:
  WindowsManagementOnlyWorkerCore() noexcept = default;

  [[nodiscard]] const ManagementOnlyRecoverySnapshot& snapshot() const noexcept {
    return coordinator_.snapshot();
  }

  void MarkLifecycleBoundary(RecoveryLifecycleBoundary boundary) noexcept {
    coordinator_.MarkLifecycleBoundary(boundary);
  }

  // Requires the complete read-only exchange snapshot (positions + pending
  // orders) together with whatever durable Quantara evidence is actually
  // available. Positions without matching durable evidence are deliberately
  // classified as external/unmanaged rather than aborting the reconciliation
  // cycle. Current stop/TP protection is recomputed inside this boundary;
  // callers cannot grant management-only authority by pre-populating protection
  // flags in durable evidence.
  [[nodiscard]] std::optional<ManagementOnlyRecoverySnapshot>
  ReconcileFreshExchangeTruth(
      const BitunixExchangeTruthSnapshot& truth,
      const std::vector<DurableReconciliationEvidence>& durable_evidence) noexcept {
    coordinator_.RequireFreshReconciliation("freshExchangeTruthRequired");

    std::vector<ExistingExchangePositionFacts> facts;
    std::vector<bool> evidence_used;
    try {
      facts.reserve(truth.positions.size());
      evidence_used.assign(durable_evidence.size(), false);
    } catch (...) {
      return std::nullopt;
    }

    for (const auto& position : truth.positions) {
      const DurableReconciliationEvidence* matched = nullptr;
      std::size_t matched_index = 0;
      for (std::size_t i = 0; i < durable_evidence.size(); ++i) {
        if (durable_evidence[i].position_id != position.position_id ||
            durable_evidence[i].symbol != position.symbol) {
          continue;
        }
        if (matched != nullptr) {
          coordinator_.RequireFreshReconciliation("duplicateDurableEvidence");
          return coordinator_.snapshot();
        }
        matched = &durable_evidence[i];
        matched_index = i;
      }

      if (matched == nullptr) {
        ExistingExchangePositionFacts external{};
        external.position_id = position.position_id;
        external.symbol = position.symbol;
        external.isolated_margin = position.margin_mode == "ISOLATION";
        external.has_conflicting_order_fill_or_history = true;
        try {
          facts.push_back(external);
        } catch (...) {
          return std::nullopt;
        }
        continue;
      }

      evidence_used[matched_index] = true;
      const auto current = ApplyCurrentExchangeProtectionEvidence(
          position, *matched, truth.pending_orders);
      if (!current.has_value()) {
        coordinator_.RequireFreshReconciliation("exchangeEvidenceJoinFailed");
        return coordinator_.snapshot();
      }
      const auto joined = BuildExistingExchangePositionFacts(position, *current);
      if (!joined.has_value()) {
        coordinator_.RequireFreshReconciliation("exchangeEvidenceJoinFailed");
        return coordinator_.snapshot();
      }
      try {
        facts.push_back(*joined);
      } catch (...) {
        return std::nullopt;
      }
    }

    for (std::size_t i = 0; i < evidence_used.size(); ++i) {
      if (!evidence_used[i]) {
        coordinator_.RequireFreshReconciliation("staleDurableEvidence");
        return coordinator_.snapshot();
      }
    }

    return coordinator_.Reconcile(facts);
  }

  [[nodiscard]] bool CanManageExistingPositions() const noexcept {
    return coordinator_.CanManageExistingPositions();
  }

  [[nodiscard]] bool CanOpenNewEntry() const noexcept {
    return false;
  }

 private:
  ManagementOnlyRecoveryCoordinator coordinator_;
};

}  // namespace quantara
