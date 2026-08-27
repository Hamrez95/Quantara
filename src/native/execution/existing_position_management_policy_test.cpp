#include "existing_position_management_policy.h"

#include <iostream>
#include <string_view>

namespace {

using quantara::EvaluateExistingPortfolio;
using quantara::ExistingExchangePositionFacts;
using quantara::ExistingPositionClassification;
using quantara::ExistingPositionManagementAuthority;

ExistingExchangePositionFacts Verified(bool managed = false) {
  return {.position_id = "position-1",
          .symbol = "BTCUSDT",
          .isolated_margin = true,
          .has_unambiguous_quantara_identity = true,
          .has_complete_exchange_stop = true,
          .has_complete_exchange_take_profit_ladder = true,
          .has_conflicting_order_fill_or_history = false,
          .has_durable_reconstruction = true,
          .is_already_managed = managed};
}

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

bool ExpectDecision(const quantara::ExistingPositionManagementDecision& decision,
                    ExistingPositionClassification classification,
                    ExistingPositionManagementAuthority authority,
                    std::string_view reason, const char* message) {
  return Expect(decision.classification == classification &&
                    decision.authority == authority &&
                    decision.blocks_new_entries && decision.reason == reason,
                message);
}

}  // namespace

int main() {
  bool ok = true;

  const auto empty = EvaluateExistingPortfolio({});
  ok &= ExpectDecision(empty, ExistingPositionClassification::kManaged,
                       ExistingPositionManagementAuthority::kNone,
                       "noOpenExchangePositions",
                       "Empty portfolio must stay disarmed and block entries.");

  const auto managed = EvaluateExistingPortfolio({Verified(true)});
  ok &= ExpectDecision(managed, ExistingPositionClassification::kManaged,
                       ExistingPositionManagementAuthority::kManageExistingOnly,
                       "allManagedVerified",
                       "Verified managed position must remain management-only.");

  const auto orphan = EvaluateExistingPortfolio({Verified()});
  ok &= ExpectDecision(orphan,
                       ExistingPositionClassification::kRecoverableOrphan,
                       ExistingPositionManagementAuthority::kManageExistingOnly,
                       "allOrphansRecoverable",
                       "Verified orphan must be management-only and block entries.");

  auto missing_identity = Verified();
  missing_identity.position_id = "";
  ok &= ExpectDecision(
      EvaluateExistingPortfolio({missing_identity}),
      ExistingPositionClassification::kAmbiguous,
      ExistingPositionManagementAuthority::kReconciliationOnly,
      "exchangePositionIdentityMissing",
      "Missing exchange identity must require reconciliation.");

  auto cross_margin = Verified();
  cross_margin.isolated_margin = false;
  ok &= ExpectDecision(EvaluateExistingPortfolio({cross_margin}),
                       ExistingPositionClassification::kExternalUnmanaged,
                       ExistingPositionManagementAuthority::kNone,
                       "crossOrUnknownMargin",
                       "Cross or unknown margin must never be managed.");

  auto external = Verified();
  external.has_unambiguous_quantara_identity = false;
  ok &= ExpectDecision(EvaluateExistingPortfolio({external}),
                       ExistingPositionClassification::kExternalUnmanaged,
                       ExistingPositionManagementAuthority::kNone,
                       "quantaraOwnershipUnproven",
                       "External position must never be managed.");

  auto missing_stop = Verified();
  missing_stop.has_complete_exchange_stop = false;
  ok &= ExpectDecision(EvaluateExistingPortfolio({missing_stop}),
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "exchangeNativeProtectionIncomplete",
                       "Missing stop must fail closed into reconciliation.");

  auto missing_take_profit = Verified();
  missing_take_profit.has_complete_exchange_take_profit_ladder = false;
  ok &= ExpectDecision(
      EvaluateExistingPortfolio({missing_take_profit}),
      ExistingPositionClassification::kAmbiguous,
      ExistingPositionManagementAuthority::kReconciliationOnly,
      "exchangeNativeProtectionIncomplete",
      "Missing take-profit ladder must fail closed into reconciliation.");

  auto conflicting_history = Verified();
  conflicting_history.has_conflicting_order_fill_or_history = true;
  ok &= ExpectDecision(EvaluateExistingPortfolio({conflicting_history}),
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "exchangeHistoryConflicts",
                       "Conflicting order/fill/history must require reconciliation.");

  auto no_reconstruction = Verified();
  no_reconstruction.has_durable_reconstruction = false;
  ok &= ExpectDecision(EvaluateExistingPortfolio({no_reconstruction}),
                       ExistingPositionClassification::kAmbiguous,
                       ExistingPositionManagementAuthority::kReconciliationOnly,
                       "durableReconstructionUnavailable",
                       "Missing durable reconstruction must require reconciliation.");

  const auto mixed_managed_orphan =
      EvaluateExistingPortfolio({Verified(true), Verified(false)});
  ok &= ExpectDecision(
      mixed_managed_orphan, ExistingPositionClassification::kRecoverableOrphan,
      ExistingPositionManagementAuthority::kManageExistingOnly,
      "allOrphansRecoverable",
      "Mixed verified managed/orphan portfolio must remain management-only.");

  const auto mixed_external = EvaluateExistingPortfolio({Verified(true), external});
  ok &= ExpectDecision(mixed_external,
                       ExistingPositionClassification::kExternalUnmanaged,
                       ExistingPositionManagementAuthority::kNone,
                       "quantaraOwnershipUnproven",
                       "One external position must block the whole portfolio.");

  return ok ? 0 : 1;
}
