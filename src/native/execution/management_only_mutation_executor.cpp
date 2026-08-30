#include "management_only_mutation_executor.h"

namespace quantara {
namespace {

constexpr ExistingPositionMutationExecutionResult Result(
    bool completed, bool submission_attempted, bool exchange_truth_reconciled,
    std::string_view reason) noexcept {
  return {completed, submission_attempted, exchange_truth_reconciled, reason};
}

}  // namespace

ExistingPositionMutationExecutionResult ExecuteExistingPositionMutation(
    const ExistingPositionManagementDecision& portfolio_decision,
    const ExistingExchangePositionFacts& position,
    const ExistingPositionMutationRequest& request,
    ExistingPositionMutationExchangePort& exchange) noexcept {
  const auto authorization = AuthorizeExistingPositionMutation(
      portfolio_decision, position, request);
  if (!authorization.allowed) {
    return Result(false, false, false, authorization.reason);
  }

  const auto submit_outcome = exchange.SubmitMutation(request);
  const auto confirmation = exchange.ConfirmMutation(request);

  switch (confirmation) {
    case ExistingPositionMutationConfirmation::kConfirmedByFreshExchangeTruth:
      return Result(true, true, true, "mutationConfirmedByExchangeTruth");
    case ExistingPositionMutationConfirmation::kNotConfirmedByFreshExchangeTruth:
      return Result(false, true, true,
                    submit_outcome == ExistingPositionMutationSubmitOutcome::
                                          kOutcomeAmbiguous
                        ? "ambiguousMutationNotConfirmed"
                        : "mutationNotConfirmed");
    case ExistingPositionMutationConfirmation::kExchangeTruthUnavailable:
      return Result(false, true, false, "postMutationExchangeTruthUnavailable");
  }

  return Result(false, true, false, "postMutationExchangeTruthUnavailable");
}

}  // namespace quantara
