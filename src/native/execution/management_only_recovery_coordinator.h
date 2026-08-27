#pragma once

#include "existing_position_management_policy.h"

#include <string_view>
#include <vector>

namespace quantara {

enum class RecoveryLifecycleBoundary {
  kRestart,
  kPowerResume,
  kNetworkRestored,
  kUpdate,
  kRollback,
};

enum class ManagementOnlyRecoveryMode {
  kDisarmed,
  kReconciliationRequired,
  kManageExistingOnly,
};

struct ManagementOnlyRecoverySnapshot final {
  ManagementOnlyRecoveryMode mode;
  ExistingPositionClassification classification;
  ExistingPositionManagementAuthority authority;
  bool blocks_new_entries;
  std::string_view reason;
};

class ManagementOnlyRecoveryCoordinator final {
 public:
  ManagementOnlyRecoveryCoordinator() noexcept;

  [[nodiscard]] const ManagementOnlyRecoverySnapshot& snapshot() const noexcept;

  // Any lifecycle boundary strips existing-position management authority until
  // fresh exchange truth is reconciled again. Credentials never affect this
  // transition and cannot auto-arm the worker.
  void MarkLifecycleBoundary(RecoveryLifecycleBoundary boundary) noexcept;

  // Reconciliation accepts exchange-truth facts only. This coordinator never
  // grants new-entry authority; verified positions can only be managed in
  // place after the shared fail-closed position policy accepts the portfolio.
  [[nodiscard]] ManagementOnlyRecoverySnapshot Reconcile(
      const std::vector<ExistingExchangePositionFacts>& positions) noexcept;

  [[nodiscard]] bool CanManageExistingPositions() const noexcept;
  [[nodiscard]] bool CanOpenNewEntry() const noexcept;

 private:
  ManagementOnlyRecoverySnapshot snapshot_;
};

}  // namespace quantara
