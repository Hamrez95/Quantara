#pragma once

#include "bitunix_exchange_truth_reader.h"
#include "bitunix_reconciliation_facts_adapter.h"
#include "../native/execution/management_only_recovery_coordinator.h"

#include <optional>
#include <string_view>
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
  // orders) together with durable Quantara evidence. Current stop/TP protection
  // is recomputed inside this boundary; callers cannot grant management-only
  // authority by pre-populating protection flags in durable evidence.
  [[nodiscard]] std::optional<ManagementOnlyRecoverySnapshot>
  ReconcileFreshExchangeTruth(
      const BitunixExchangeTruthSnapshot& truth,
      const std::vector<DurableReconciliationEvidence>& durable_evidence) noexcept {
    coordinator_.RequireFreshReconciliation("freshExchangeTruthRequired");

    if (truth.positions.size() != durable_evidence.size()) {
      return std::nullopt;
    }

    std::vector<ExistingExchangePositionFacts> facts;
    try {
      facts.reserve(truth.positions.size());
    } catch (...) {
      return std::nullopt;
    }
    std::vector<bool> evidence_used;
    try {
      evidence_used.assign(durable_evidence.size(), false);
    } catch (...) {
      return std::nullopt;
    }

    for (const auto& position : truth.positions) {
      std::optional<DurableReconciliationEvidence> matched;
      std::size_t matched_index = 0;
      for (std::size_t i = 0; i < durable_evidence.size(); ++i) {
        if (evidence_used[i] ||
            durable_evidence[i].position_id != position.position_id ||
            durable_evidence[i].symbol != position.symbol) {
          continue;
        }
        if (matched.has_value()) {
          return std::nullopt;
        }
        matched = ApplyCurrentExchangeProtectionEvidence(
            position, durable_evidence[i], truth.pending_orders);
        if (!matched.has_value()) {
          return std::nullopt;
        }
        matched_index = i;
      }
      if (!matched.has_value()) {
        return std::nullopt;
      }
      evidence_used[matched_index] = true;

      const auto position_facts =
          BuildExistingExchangePositionFacts(position, *matched);
      if (!position_facts.has_value()) {
        return std::nullopt;
      }
      try {
        facts.push_back(*position_facts);
      } catch (...) {
        return std::nullopt;
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
