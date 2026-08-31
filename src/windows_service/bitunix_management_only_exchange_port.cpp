#include "bitunix_management_only_exchange_port.h"

#include "bitunix_management_only_request.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cctype>
#include <string_view>
#include <utility>

namespace quantara {
namespace {

bool IsSafeIdentityToken(std::string_view value, std::size_t max_size) noexcept {
  return !value.empty() && value.size() <= max_size &&
         std::all_of(value.begin(), value.end(), [](const char ch) {
           return std::isalnum(static_cast<unsigned char>(ch)) != 0 || ch == '_' ||
                  ch == '-';
         });
}

bool IsSafeConfirmationRequest(
    const ExistingPositionMutationRequest& request) noexcept {
  if (!request.reduce_only || request.increases_exposure ||
      request.changes_margin_mode || request.widens_stop ||
      !IsSafeIdentityToken(request.position_id, 128) ||
      !IsSafeIdentityToken(request.symbol, 32)) {
    return false;
  }

  switch (request.kind) {
    case ExistingPositionMutationKind::kReduceOnlyClose:
      return BuildBitunixManagementOnlyRequest(request).has_value();
    case ExistingPositionMutationKind::kTightenStop:
      return std::isfinite(request.new_stop_price) && request.new_stop_price > 0.0;
    case ExistingPositionMutationKind::kUnsupported:
      return false;
  }
  return false;
}

bool PriceMatches(std::string_view exchange_price, double expected) noexcept {
  if (exchange_price.empty() || !std::isfinite(expected) || expected <= 0.0) {
    return false;
  }

  double actual = 0.0;
  const auto parsed = std::from_chars(exchange_price.data(),
                                      exchange_price.data() + exchange_price.size(),
                                      actual);
  if (parsed.ec != std::errc{} ||
      parsed.ptr != exchange_price.data() + exchange_price.size() ||
      !std::isfinite(actual) || actual <= 0.0) {
    return false;
  }

  const double scaled_tolerance = std::abs(expected) * 1e-10;
  const double tolerance = scaled_tolerance > 1e-12 ? scaled_tolerance : 1e-12;
  return std::abs(actual - expected) <= tolerance;
}

ExistingPositionMutationConfirmation ConfirmClose(
    const BitunixExchangeTruthSnapshot& truth,
    const ExistingPositionMutationRequest& request) noexcept {
  for (const auto& position : truth.positions) {
    if (position.position_id == request.position_id ||
        position.symbol == request.symbol) {
      return ExistingPositionMutationConfirmation::
          kNotConfirmedByFreshExchangeTruth;
    }
  }

  for (const auto& order : truth.pending_orders.orders) {
    if ((!order.position_id.empty() && order.position_id == request.position_id) ||
        order.symbol == request.symbol) {
      return ExistingPositionMutationConfirmation::
          kNotConfirmedByFreshExchangeTruth;
    }
  }

  for (const auto& order : truth.pending_tpsl_orders) {
    if (order.position_id == request.position_id || order.symbol == request.symbol) {
      return ExistingPositionMutationConfirmation::
          kNotConfirmedByFreshExchangeTruth;
    }
  }

  return ExistingPositionMutationConfirmation::kConfirmedByFreshExchangeTruth;
}

ExistingPositionMutationConfirmation ConfirmTightenedStop(
    const BitunixExchangeTruthSnapshot& truth,
    const ExistingPositionMutationRequest& request) noexcept {
  std::size_t matching_positions = 0;
  for (const auto& position : truth.positions) {
    const bool same_id = position.position_id == request.position_id;
    const bool same_symbol = position.symbol == request.symbol;
    if (same_id != same_symbol) {
      return ExistingPositionMutationConfirmation::
          kNotConfirmedByFreshExchangeTruth;
    }
    if (same_id && same_symbol) {
      ++matching_positions;
    }
  }
  if (matching_positions != 1) {
    return ExistingPositionMutationConfirmation::
        kNotConfirmedByFreshExchangeTruth;
  }

  std::size_t stop_orders = 0;
  bool expected_stop_observed = false;
  for (const auto& order : truth.pending_tpsl_orders) {
    const bool same_id = order.position_id == request.position_id;
    const bool same_symbol = order.symbol == request.symbol;
    if (same_id != same_symbol) {
      return ExistingPositionMutationConfirmation::
          kNotConfirmedByFreshExchangeTruth;
    }
    if (!same_id || !same_symbol || order.stop_loss_price.empty()) {
      continue;
    }
    ++stop_orders;
    expected_stop_observed =
        expected_stop_observed || PriceMatches(order.stop_loss_price,
                                                request.new_stop_price);
  }

  if (stop_orders != 1 || !expected_stop_observed) {
    return ExistingPositionMutationConfirmation::
        kNotConfirmedByFreshExchangeTruth;
  }
  return ExistingPositionMutationConfirmation::kConfirmedByFreshExchangeTruth;
}

}  // namespace

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
  if (read_only_transport_ == nullptr || !IsSafeConfirmationRequest(request)) {
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

  switch (request.kind) {
    case ExistingPositionMutationKind::kReduceOnlyClose:
      return ConfirmClose(*truth, request);
    case ExistingPositionMutationKind::kTightenStop:
      return ConfirmTightenedStop(*truth, request);
    case ExistingPositionMutationKind::kUnsupported:
      return ExistingPositionMutationConfirmation::kExchangeTruthUnavailable;
  }
  return ExistingPositionMutationConfirmation::kExchangeTruthUnavailable;
}

}  // namespace quantara
