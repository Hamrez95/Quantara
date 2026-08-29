#pragma once

#include "bitunix_exchange_truth_reader.h"
#include "bitunix_management_only_reconciliation.h"
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
  // classified as external/unmanaged by the shared reconciliation policy; they
  // must not make the worker abort before that safety classification is made.
  // Current stop/TP protection is recomputed inside the shared boundary and
  // callers cannot grant management-only authority by pre-populating protection
  // flags in durable evidence.
  [[nodiscard]] std::optional<ManagementOnlyRecoverySnapshot>
  ReconcileFreshExchangeTruth(
      const BitunixExchangeTruthSnapshot& truth,
      const std::vector<DurableReconciliationEvidence>& durable_evidence) noexcept {
    return ReconcileBitunixManagementOnly(truth, durable_evidence, coordinator_);
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
