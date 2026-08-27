#include "existing_position_management_policy.h"

namespace quantara {
namespace {

constexpr ExistingPositionManagementDecision Decision(
    ExistingPositionClassification classification,
    ExistingPositionManagementAuthority authority, std::string_view reason) {
  return {classification, authority, true, reason};
}

bool HasIdentity(const ExistingExchangePositionFacts& facts) noexcept {
  return !facts.position_id.empty() && !facts.symbol.empty();
}

bool HasVerifiedProtection(const ExistingExchangePositionFacts& facts) noexcept {
  return facts.has_complete_exchange_stop &&
         facts.has_complete_exchange_take_profit_ladder;
}

}  // namespace

ExistingPositionManagementDecision ClassifyExistingExchangePosition(
    const ExistingExchangePositionFacts& facts) noexcept {
  if (!HasIdentity(facts)) {
    return Decision(ExistingPositionClassification::kAmbiguous,
                    ExistingPositionManagementAuthority::kReconciliationOnly,
                    "exchangePositionIdentityMissing");
  }
  if (!facts.isolated_margin) {
    return Decision(ExistingPositionClassification::kExternalUnmanaged,
                    ExistingPositionManagementAuthority::kNone,
                    "crossOrUnknownMargin");
  }
  if (!facts.has_unambiguous_quantara_identity) {
    return Decision(ExistingPositionClassification::kExternalUnmanaged,
                    ExistingPositionManagementAuthority::kNone,
                    "quantaraOwnershipUnproven");
  }
  if (!HasVerifiedProtection(facts)) {
    return Decision(ExistingPositionClassification::kAmbiguous,
                    ExistingPositionManagementAuthority::kReconciliationOnly,
                    "exchangeNativeProtectionIncomplete");
  }
  if (facts.has_conflicting_order_fill_or_history) {
    return Decision(ExistingPositionClassification::kAmbiguous,
                    ExistingPositionManagementAuthority::kReconciliationOnly,
                    "exchangeHistoryConflicts");
  }
  if (!facts.has_durable_reconstruction) {
    return Decision(ExistingPositionClassification::kAmbiguous,
                    ExistingPositionManagementAuthority::kReconciliationOnly,
                    "durableReconstructionUnavailable");
  }
  return Decision(facts.is_already_managed
                      ? ExistingPositionClassification::kManaged
                      : ExistingPositionClassification::kRecoverableOrphan,
                  ExistingPositionManagementAuthority::kManageExistingOnly,
                  facts.is_already_managed ? "managedVerified"
                                           : "recoverableOrphanVerified");
}

ExistingPositionManagementDecision EvaluateExistingPortfolio(
    const std::vector<ExistingExchangePositionFacts>& positions) noexcept {
  if (positions.empty()) {
    return Decision(ExistingPositionClassification::kManaged,
                    ExistingPositionManagementAuthority::kNone,
                    "noOpenExchangePositions");
  }
  bool any_recoverable = false;
  for (const auto& position : positions) {
    const auto decision = ClassifyExistingExchangePosition(position);
    if (decision.authority !=
        ExistingPositionManagementAuthority::kManageExistingOnly) {
      return decision;
    }
    any_recoverable = any_recoverable ||
                      decision.classification ==
                          ExistingPositionClassification::kRecoverableOrphan;
  }
  return Decision(any_recoverable
                      ? ExistingPositionClassification::kRecoverableOrphan
                      : ExistingPositionClassification::kManaged,
                  ExistingPositionManagementAuthority::kManageExistingOnly,
                  any_recoverable ? "allOrphansRecoverable" : "allManagedVerified");
}

}  // namespace quantara
