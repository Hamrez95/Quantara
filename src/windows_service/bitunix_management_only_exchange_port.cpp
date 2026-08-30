#include "bitunix_management_only_exchange_port.h"

#include "bitunix_management_only_request.h"

#include <utility>

namespace quantara {

BitunixManagementOnlyExchangePort::BitunixManagementOnlyExchangePort(
    std::filesystem::path credential_root,
    BitunixManagementOnlyTransport mutation_transport,
    BitunixReadOnlyTransport read_only_transport,
    BitunixManagementOnlyHttpsLimits mutation_limits,
    BitunixHttpsReadOnlyLimits read_only_limits) noexcept
    : credential_root_(std::move(credential_root)),
      mutation_transport_(mutation_transport),
      read_only_transport_(read_only_transport),
      mutation_limits_(mutation_limits),
      read_only_limits_(read_only_limits) {}

ExistingPositionMutationSubmitOutcome
BitunixManagementOnlyExchangePort::SubmitMutation(
    const ExistingPositionMutationRequest& request) noexcept {
  if (mutation_transport_ == nullptr) {
    return ExistingPositionMutationSubmitOutcome::kDefinitelyNotSubmitted;
  }

  const auto mutation_request = BuildBitunixManagementOnlyRequest(request);
  if (!mutation_request.has_value()) {
    return ExistingPositionMutationSubmitOutcome::kDefinitelyNotSubmitted;
  }

  const auto auth = GenerateBitunixReadOnlyAuthStamp();
  if (!auth.has_value()) {
    return ExistingPositionMutationSubmitOutcome::kDefinitelyNotSubmitted;
  }

  const auto envelope = BuildBitunixManagementOnlyHttpEnvelope(
      credential_root_, *mutation_request, auth->nonce, auth->timestamp);
  if (!envelope.has_value()) {
    return ExistingPositionMutationSubmitOutcome::kDefinitelyNotSubmitted;
  }

  const auto response = mutation_transport_(*envelope, mutation_limits_);
  if (!response.has_value() || response->status_code != 200) {
    // Once WinHTTP is entered, a missing/non-success response is treated as an
    // unknown submission outcome. The shared executor will reconcile before any
    // later attempt and this port never performs a blind retry.
    return ExistingPositionMutationSubmitOutcome::kOutcomeAmbiguous;
  }

  return ExistingPositionMutationSubmitOutcome::kAcknowledged;
}

ExistingPositionMutationConfirmation
BitunixManagementOnlyExchangePort::ConfirmMutation(
    const ExistingPositionMutationRequest& request) noexcept {
  if (read_only_transport_ == nullptr ||
      !BuildBitunixManagementOnlyRequest(request).has_value()) {
    return ExistingPositionMutationConfirmation::kExchangeTruthUnavailable;
  }

  const auto positions_auth = GenerateBitunixReadOnlyAuthStamp();
  const auto orders_auth = GenerateBitunixReadOnlyAuthStamp();
  if (!positions_auth.has_value() || !orders_auth.has_value()) {
    return ExistingPositionMutationConfirmation::kExchangeTruthUnavailable;
  }

  const auto truth = ReadBitunixExchangeTruth(
      credential_root_, *positions_auth, *orders_auth, read_only_transport_,
      read_only_limits_);
  if (!truth.has_value()) {
    return ExistingPositionMutationConfirmation::kExchangeTruthUnavailable;
  }

  for (const auto& position : truth->positions) {
    if (position.position_id == request.position_id ||
        position.symbol == request.symbol) {
      return ExistingPositionMutationConfirmation::
          kNotConfirmedByFreshExchangeTruth;
    }
  }

  for (const auto& order : truth->pending_orders.orders) {
    if ((!order.position_id.empty() && order.position_id == request.position_id) ||
        order.symbol == request.symbol) {
      return ExistingPositionMutationConfirmation::
          kNotConfirmedByFreshExchangeTruth;
    }
  }

  return ExistingPositionMutationConfirmation::kConfirmedByFreshExchangeTruth;
}

}  // namespace quantara
