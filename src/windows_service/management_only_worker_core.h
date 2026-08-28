#pragma once

#include "bitunix_exchange_truth_parser.h"
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

  [[nodiscard]] std::optional<ManagementOnlyRecoverySnapshot>
  ReconcileFreshExchangeTruth(
      const std::vector<BitunixPendingPosition>& positions,
      const std::vector<DurableReconciliationEvidence>& evidence) noexcept {
    coordinator_.RequireFreshReconciliation("freshExchangeTruthRequired");

    if (positions.size() != evidence.size()) {
      return std::nullopt;
    }

    std::vector<ExistingExchangePositionFacts> facts;
    facts.reserve(positions.size());
    std::vector<bool> evidence_used(evidence.size(), false);

    for (const auto& position : positions) {
      std::optional<ExistingExchangePositionFacts> matched;
      std::size_t matched_index = 0;
      for (std::size_t i = 0; i < evidence.size(); ++i) {
        if (evidence_used[i] || evidence[i].position_id != position.position_id ||
            evidence[i].symbol != position.symbol) {
          continue;
        }
        if (matched.has_value()) {
          return std::nullopt;
        }
        matched = BuildExistingExchangePositionFacts(position, evidence[i]);
        matched_index = i;
      }
      if (!matched.has_value()) {
        return std::nullopt;
      }
      evidence_used[matched_index] = true;
      facts.push_back(*matched);
    }

    const auto result = coordinator_.Reconcile(facts);
    return result;
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
