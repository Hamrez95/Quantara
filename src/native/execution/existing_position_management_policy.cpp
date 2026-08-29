#include "existing_position_management_policy.h"

namespace quantara {
namespace {

constexpr ExistingPositionManagementDecision Decision(
    ExistingPositionClassification classification,
    ExistingPositionManagementAuthority authority, std::string_view reason) {
  return {classification, authority, true, reason};
}

constexpr ExistingPositionMutationDecision MutationDecision(
    bool allowed, std::string_view reason) {
  return {allowed, reason};
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

ExistingPositionMutationDecision AuthorizeExistingPositionMutation(
    const ExistingPositionManagementDecision& portfolio_decision,
    const ExistingExchangePositionFacts& position,
    const ExistingPositionMutationRequest& request) noexcept {
  if (portfolio_decision.authority !=
          ExistingPositionManagementAuthority::kManageExistingOnly ||
      !portfolio_decision.blocks_new_entries) {
    return MutationDecision(false, "managementAuthorityUnavailable");
  }

  const auto current = ClassifyExistingExchangePosition(position);
  if (current.authority !=
      ExistingPositionManagementAuthority::kManageExistingOnly) {
    return MutationDecision(false, "positionNoLongerManageable");
  }

  if (request.position_id.empty() || request.symbol.empty() ||
      request.position_id != position.position_id ||
      request.symbol != position.symbol) {
    return MutationDecision(false, "positionIdentityMismatch");
  }
  if (!request.reduce_only) {
    return MutationDecision(false, "reduceOnlyRequired");
  }
  if (request.increases_exposure) {
    return MutationDecision(false, "exposureIncreaseForbidden");
  }
  if (request.changes_margin_mode) {
    return MutationDecision(false, "marginModeChangeForbidden");
  }

  switch (request.kind) {
    case ExistingPositionMutationKind::kReduceOnlyClose:
      return MutationDecision(true, "reduceOnlyCloseAuthorized");
    case ExistingPositionMutationKind::kTightenStop:
      if (request.widens_stop) {
        return MutationDecision(false, "stopWideningForbidden");
      }
      return MutationDecision(true, "tightenStopAuthorized");
    case ExistingPositionMutationKind::kUnsupported:
      return MutationDecision(false, "unsupportedManagementMutation");
  }

  return MutationDecision(false, "unsupportedManagementMutation");
}

}  // namespace quantara
