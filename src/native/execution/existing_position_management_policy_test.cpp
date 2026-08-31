#include "existing_position_management_policy.h"

#include <iostream>
#include <limits>
#include <string_view>

namespace {

using quantara::AuthorizeExistingPositionMutation;
using quantara::EvaluateExistingPortfolio;
using quantara::ExistingExchangePositionFacts;
using quantara::ExistingPositionClassification;
using quantara::ExistingPositionManagementAuthority;
using quantara::ExistingPositionMutationKind;
using quantara::ExistingPositionMutationRequest;
using quantara::ExistingPositionSide;

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

ExistingPositionMutationRequest SafeMutation(ExistingPositionMutationKind kind) {
  return {.kind = kind,
          .position_id = "position-1",
          .symbol = "BTCUSDT",
          .reduce_only = true,
          .increases_exposure = false,
          .changes_margin_mode = false,
          .widens_stop = false};
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

bool ExpectMutation(
    const quantara::ExistingPositionMutationDecision& decision, bool allowed,
    std::string_view reason, const char* message) {
  return Expect(decision.allowed == allowed && decision.reason == reason, message);
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

  const auto verified_position = Verified(true);
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(
          managed, verified_position,
          SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose)),
      true, "reduceOnlyCloseAuthorized",
      "Verified management-only authority must permit an exact reduce-only close.");

  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(
          managed, verified_position,
          SafeMutation(ExistingPositionMutationKind::kTightenStop)),
      false, "stopPriceEvidenceRequired",
      "Stop tightening must fail closed until current/new stop prices and side are explicit policy evidence.");

  auto long_position = verified_position;
  long_position.side = ExistingPositionSide::kLong;
  long_position.current_stop_price = 60000.0;
  auto long_tighten = SafeMutation(ExistingPositionMutationKind::kTightenStop);
  long_tighten.new_stop_price = 60500.0;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, long_position, long_tighten),
      true, "tightenStopAuthorized",
      "Long stop must be authorized only when the explicit new price is above the fresh exchange stop.");

  auto long_not_tighter = long_tighten;
  long_not_tighter.new_stop_price = 59500.0;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, long_position, long_not_tighter),
      false, "stopNotTighter",
      "Long stop moving down must fail closed even when the caller claims no widening.");

  auto short_position = verified_position;
  short_position.side = ExistingPositionSide::kShort;
  short_position.current_stop_price = 70000.0;
  auto short_tighten = SafeMutation(ExistingPositionMutationKind::kTightenStop);
  short_tighten.new_stop_price = 69500.0;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, short_position, short_tighten),
      true, "tightenStopAuthorized",
      "Short stop must be authorized only when the explicit new price is below the fresh exchange stop.");

  auto equal_stop = short_tighten;
  equal_stop.new_stop_price = short_position.current_stop_price;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, short_position, equal_stop),
      false, "stopNotTighter",
      "An unchanged stop is not a tightening mutation.");

  auto invalid_stop = long_tighten;
  invalid_stop.new_stop_price = std::numeric_limits<double>::infinity();
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, long_position, invalid_stop),
      false, "stopPriceEvidenceRequired",
      "Non-finite requested stop evidence must fail closed.");

  auto wrong_identity =
      SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose);
  wrong_identity.position_id = "position-2";
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, verified_position,
                                        wrong_identity),
      false, "positionIdentityMismatch",
      "A mutation for another position identity must fail closed.");

  auto non_reduce_only =
      SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose);
  non_reduce_only.reduce_only = false;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, verified_position,
                                        non_reduce_only),
      false, "reduceOnlyRequired",
      "Management-only mutations must never omit reduce-only semantics.");

  auto increases_exposure =
      SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose);
  increases_exposure.increases_exposure = true;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, verified_position,
                                        increases_exposure),
      false, "exposureIncreaseForbidden",
      "Management-only mutations must never increase exposure.");

  auto changes_margin =
      SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose);
  changes_margin.changes_margin_mode = true;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, verified_position,
                                        changes_margin),
      false, "marginModeChangeForbidden",
      "Management-only mutations must never change margin mode.");

  auto widens_stop = SafeMutation(ExistingPositionMutationKind::kTightenStop);
  widens_stop.widens_stop = true;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(managed, verified_position, widens_stop),
      false, "stopWideningForbidden",
      "Management-only stop changes must never widen risk.");

  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(
          empty, verified_position,
          SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose)),
      false, "managementAuthorityUnavailable",
      "No-open-position portfolio state must not grant mutation authority.");

  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(
          mixed_external, verified_position,
          SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose)),
      false, "managementAuthorityUnavailable",
      "An external position in the portfolio must block all management mutations.");

  auto degraded_position = verified_position;
  degraded_position.has_complete_exchange_stop = false;
  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(
          managed, degraded_position,
          SafeMutation(ExistingPositionMutationKind::kReduceOnlyClose)),
      false, "positionNoLongerManageable",
      "A position that lost verified protection must be reconciled before mutation.");

  ok &= ExpectMutation(
      AuthorizeExistingPositionMutation(
          managed, verified_position,
          SafeMutation(ExistingPositionMutationKind::kUnsupported)),
      false, "unsupportedManagementMutation",
      "Unknown management mutations must fail closed.");

  return ok ? 0 : 1;
}
