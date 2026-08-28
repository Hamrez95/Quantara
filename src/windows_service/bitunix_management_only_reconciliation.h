#pragma once

#include <vector>

#include "bitunix_exchange_truth_reader.h"
#include "bitunix_reconciliation_facts_adapter.h"
#include "../native/execution/management_only_recovery_coordinator.h"

namespace quantara {

// Performs one fail-closed reconciliation of parsed Bitunix exchange truth
// against explicit durable Quantara evidence. Exchange positions without
// matching durable evidence are treated as external/unmanaged. Durable evidence
// that does not match a current exchange position is rejected as stale/drifted.
// This function can grant management of verified existing positions only;
// new-entry authority remains impossible by coordinator contract.
[[nodiscard]] ManagementOnlyRecoverySnapshot ReconcileBitunixManagementOnly(
    const BitunixExchangeTruthSnapshot& exchange_truth,
    const std::vector<DurableReconciliationEvidence>& durable_evidence,
    ManagementOnlyRecoveryCoordinator& coordinator) noexcept;

}  // namespace quantara
