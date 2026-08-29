#include "management_only_mutation_executor.h"

#include <iostream>
#include <string_view>

namespace {

using quantara::EvaluateExistingPortfolio;
using quantara::ExistingExchangePositionFacts;
using quantara::ExistingPositionMutationConfirmation;
using quantara::ExistingPositionMutationExchangePort;
using quantara::ExistingPositionMutationKind;
using quantara::ExistingPositionMutationRequest;
using quantara::ExistingPositionMutationSubmitOutcome;
using quantara::ExecuteExistingPositionMutation;

ExistingExchangePositionFacts VerifiedPosition() {
  return {.position_id = "position-1",
          .symbol = "BTCUSDT",
          .has_quantara_identity = true,
          .isolated_margin = true,
          .has_complete_exchange_stop = true,
          .has_complete_tp_ladder = true,
          .has_conflicting_exchange_history = false,
          .has_durable_reconstruction = true,
          .is_already_managed = true};
}

ExistingPositionMutationRequest SafeClose() {
  return {.kind = ExistingPositionMutationKind::kReduceOnlyClose,
          .position_id = "position-1",
          .symbol = "BTCUSDT",
          .reduce_only = true,
          .increases_exposure = false,
          .changes_margin_mode = false,
          .widens_stop = false};
}

class FakeExchange final : public ExistingPositionMutationExchangePort {
 public:
  ExistingPositionMutationSubmitOutcome submit_outcome =
      ExistingPositionMutationSubmitOutcome::kAcknowledged;
  ExistingPositionMutationConfirmation confirmation =
      ExistingPositionMutationConfirmation::kConfirmedByFreshExchangeTruth;
  int submit_calls = 0;
  int confirm_calls = 0;

  ExistingPositionMutationSubmitOutcome SubmitMutation(
      const ExistingPositionMutationRequest&) noexcept override {
    ++submit_calls;
    return submit_outcome;
  }

  ExistingPositionMutationConfirmation ConfirmMutation(
      const ExistingPositionMutationRequest&) noexcept override {
    ++confirm_calls;
    return confirmation;
  }
};

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

}  // namespace

int main() {
  bool ok = true;
  const auto position = VerifiedPosition();
  const auto portfolio = EvaluateExistingPortfolio({position});

  FakeExchange acknowledged;
  const auto confirmed = ExecuteExistingPositionMutation(
      portfolio, position, SafeClose(), acknowledged);
  ok &= Expect(confirmed.completed && confirmed.submission_attempted &&
                   confirmed.exchange_truth_reconciled &&
                   confirmed.reason == "mutationConfirmedByExchangeTruth" &&
                   acknowledged.submit_calls == 1 &&
                   acknowledged.confirm_calls == 1,
               "ACK must only succeed after fresh exchange confirmation.");

  FakeExchange ack_without_truth;
  ack_without_truth.confirmation =
      ExistingPositionMutationConfirmation::kNotConfirmedByFreshExchangeTruth;
  const auto unconfirmed = ExecuteExistingPositionMutation(
      portfolio, position, SafeClose(), ack_without_truth);
  ok &= Expect(!unconfirmed.completed && unconfirmed.exchange_truth_reconciled &&
                   unconfirmed.reason == "mutationNotConfirmed" &&
                   ack_without_truth.confirm_calls == 1,
               "ACK without confirmed exchange truth must fail closed.");

  FakeExchange ambiguous_confirmed;
  ambiguous_confirmed.submit_outcome =
      ExistingPositionMutationSubmitOutcome::kOutcomeAmbiguous;
  const auto recovered = ExecuteExistingPositionMutation(
      portfolio, position, SafeClose(), ambiguous_confirmed);
  ok &= Expect(recovered.completed &&
                   recovered.reason == "mutationConfirmedByExchangeTruth" &&
                   ambiguous_confirmed.confirm_calls == 1,
               "Ambiguous transport outcome may succeed only when exchange truth confirms it.");

  FakeExchange ambiguous_not_confirmed;
  ambiguous_not_confirmed.submit_outcome =
      ExistingPositionMutationSubmitOutcome::kOutcomeAmbiguous;
  ambiguous_not_confirmed.confirmation =
      ExistingPositionMutationConfirmation::kNotConfirmedByFreshExchangeTruth;
  const auto ambiguous_failure = ExecuteExistingPositionMutation(
      portfolio, position, SafeClose(), ambiguous_not_confirmed);
  ok &= Expect(!ambiguous_failure.completed &&
                   ambiguous_failure.reason == "ambiguousMutationNotConfirmed" &&
                   ambiguous_not_confirmed.confirm_calls == 1,
               "Ambiguous mutation must never trigger a blind success or retry.");

  FakeExchange truth_unavailable;
  truth_unavailable.confirmation =
      ExistingPositionMutationConfirmation::kExchangeTruthUnavailable;
  const auto unavailable = ExecuteExistingPositionMutation(
      portfolio, position, SafeClose(), truth_unavailable);
  ok &= Expect(!unavailable.completed && !unavailable.exchange_truth_reconciled &&
                   unavailable.reason == "postMutationExchangeTruthUnavailable",
               "Unavailable post-mutation truth must fail closed.");

  FakeExchange definitely_not_submitted_but_truth_changed;
  definitely_not_submitted_but_truth_changed.submit_outcome =
      ExistingPositionMutationSubmitOutcome::kDefinitelyNotSubmitted;
  const auto truth_wins = ExecuteExistingPositionMutation(
      portfolio, position, SafeClose(), definitely_not_submitted_but_truth_changed);
  ok &= Expect(truth_wins.completed &&
                   definitely_not_submitted_but_truth_changed.confirm_calls == 1,
               "Fresh exchange truth must remain authoritative even when transport reports no submit.");

  auto unsafe = SafeClose();
  unsafe.reduce_only = false;
  FakeExchange blocked;
  const auto rejected = ExecuteExistingPositionMutation(
      portfolio, position, unsafe, blocked);
  ok &= Expect(!rejected.completed && !rejected.submission_attempted &&
                   !rejected.exchange_truth_reconciled &&
                   rejected.reason == "reduceOnlyRequired" &&
                   blocked.submit_calls == 0 && blocked.confirm_calls == 0,
               "Policy rejection must happen before any exchange mutation call.");

  auto wrong_identity = SafeClose();
  wrong_identity.position_id = "position-2";
  FakeExchange wrong;
  const auto mismatch = ExecuteExistingPositionMutation(
      portfolio, position, wrong_identity, wrong);
  ok &= Expect(!mismatch.completed && mismatch.reason == "positionIdentityMismatch" &&
                   wrong.submit_calls == 0 && wrong.confirm_calls == 0,
               "Mismatched position identity must never reach exchange transport.");

  return ok ? 0 : 1;
}
