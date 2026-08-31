#include "bitunix_management_only_exchange_port.h"

#include <windows.h>

#include <filesystem>
#include <iostream>
#include <optional>
#include <string>

#include "credential_vault.h"

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

std::filesystem::path TestRoot() {
  wchar_t temp_path[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length >= MAX_PATH) return {};
  return std::filesystem::path(temp_path) /
         (L"quantara-bitunix-management-port-" +
          std::to_wstring(GetCurrentProcessId()));
}

std::optional<quantara::BitunixManagementOnlyHttpsResponse> AckTransport(
    const quantara::BitunixManagementOnlyHttpEnvelope& envelope,
    const quantara::BitunixManagementOnlyHttpsLimits&) noexcept {
  if (envelope.method != "POST") return std::nullopt;

  const bool valid_close =
      envelope.resource == "/api/v1/futures/trade/flash_close_position" &&
      envelope.body == R"json({"positionId":"12345"})json";
  const bool valid_tighten =
      envelope.resource == "/api/v1/futures/tpsl/position/modify_order" &&
      envelope.body ==
          R"json({"symbol":"BTCUSDT","positionId":"12345","slPrice":"65000","slStopType":"MARK_PRICE"})json";
  if (!valid_close && !valid_tighten) return std::nullopt;

  return quantara::BitunixManagementOnlyHttpsResponse{
      200, R"json({"code":0})json"};
}

std::optional<quantara::BitunixManagementOnlyHttpsResponse> AmbiguousTransport(
    const quantara::BitunixManagementOnlyHttpEnvelope&,
    const quantara::BitunixManagementOnlyHttpsLimits&) noexcept {
  return std::nullopt;
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> EmptyTpSlTruth(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope) noexcept {
  if (envelope.resource ==
      "/api/v1/futures/tpsl/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":[]})json"};
  }
  return std::nullopt;
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> ClosedTruthTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  if (envelope.resource.find("/position/get_pending_positions") !=
      std::string::npos) {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":[]})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/trade/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":{"orderList":[],"total":0}})json"};
  }
  return EmptyTpSlTruth(envelope);
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> StillOpenTruthTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  if (envelope.resource.find("/position/get_pending_positions") !=
      std::string::npos) {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"positionId":"12345","symbol":"BTCUSDT","qty":"0.001","side":"LONG","marginMode":"ISOLATION","positionMode":"ONE_WAY","leverage":5}]})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/trade/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":{"orderList":[],"total":0}})json"};
  }
  return EmptyTpSlTruth(envelope);
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> StaleOrderTruthTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  if (envelope.resource.find("/position/get_pending_positions") !=
      std::string::npos) {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":[]})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/trade/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":{"orderList":[{"orderId":"sl-1","positionId":"12345","symbol":"BTCUSDT","status":"NEW","reduceOnly":true,"slPrice":"60000"}],"total":1}})json"};
  }
  return EmptyTpSlTruth(envelope);
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> TightenedStopTruthTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  if (envelope.resource.find("/position/get_pending_positions") !=
      std::string::npos) {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"positionId":"12345","symbol":"BTCUSDT","qty":"0.001","side":"LONG","marginMode":"ISOLATION","positionMode":"ONE_WAY","leverage":5}]})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/trade/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":{"orderList":[],"total":0}})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/tpsl/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"id":"sl-1","positionId":"12345","symbol":"BTCUSDT","tpPrice":"70000","slPrice":"65000.000000","slStopType":"MARK_PRICE","tpQty":"0.001","slQty":"0.001"}]})json"};
  }
  return std::nullopt;
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> WrongTriggerTruthTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits& limits) noexcept {
  if (envelope.resource ==
      "/api/v1/futures/tpsl/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"id":"sl-1","positionId":"12345","symbol":"BTCUSDT","tpPrice":"70000","slPrice":"65000.000000","slStopType":"LAST_PRICE","tpQty":"0.001","slQty":"0.001"}]})json"};
  }
  return TightenedStopTruthTransport(envelope, limits);
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> WrongStopTruthTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  if (envelope.resource.find("/position/get_pending_positions") !=
      std::string::npos) {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"positionId":"12345","symbol":"BTCUSDT","qty":"0.001","side":"LONG","marginMode":"ISOLATION","positionMode":"ONE_WAY","leverage":5}]})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/trade/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":{"orderList":[],"total":0}})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/tpsl/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"id":"sl-1","positionId":"12345","symbol":"BTCUSDT","tpPrice":"70000","slPrice":"64000","slStopType":"MARK_PRICE","tpQty":"0.001","slQty":"0.001"}]})json"};
  }
  return std::nullopt;
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> DuplicateStopTruthTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  if (envelope.resource.find("/position/get_pending_positions") !=
      std::string::npos) {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"positionId":"12345","symbol":"BTCUSDT","qty":"0.001","side":"LONG","marginMode":"ISOLATION","positionMode":"ONE_WAY","leverage":5}]})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/trade/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{
        200, R"json({"code":0,"data":{"orderList":[],"total":0}})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/tpsl/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{200,
        R"json({"code":0,"data":[{"id":"sl-1","positionId":"12345","symbol":"BTCUSDT","slPrice":"65000","slStopType":"MARK_PRICE","slQty":"0.001"},{"id":"sl-2","positionId":"12345","symbol":"BTCUSDT","slPrice":"65000","slStopType":"MARK_PRICE","slQty":"0.001"}]})json"};
  }
  return std::nullopt;
}

quantara::ExistingPositionMutationRequest CloseRequest() {
  return quantara::ExistingPositionMutationRequest{
      .kind = quantara::ExistingPositionMutationKind::kReduceOnlyClose,
      .position_id = "12345",
      .symbol = "BTCUSDT",
      .reduce_only = true,
      .increases_exposure = false,
      .changes_margin_mode = false,
      .widens_stop = false,
  };
}

quantara::ExistingPositionMutationRequest TightenStopRequest() {
  return quantara::ExistingPositionMutationRequest{
      .kind = quantara::ExistingPositionMutationKind::kTightenStop,
      .position_id = "12345",
      .symbol = "BTCUSDT",
      .reduce_only = true,
      .increases_exposure = false,
      .changes_margin_mode = false,
      .widens_stop = false,
      .new_stop_price = 65000.0,
      .stop_trigger_type = "MARK_PRICE",
  };
}

}  // namespace

int main() {
  bool ok = true;
  const auto root = TestRoot();
  ok &= Expect(!root.empty(), "Temporary credential root must be available.");
  if (root.empty()) return 1;

  std::error_code ignored;
  std::filesystem::remove_all(root, ignored);

  try {
    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-api-key", "demo-api");
    vault.Store(L"bitunix-api-secret", "demo-secret");

    const auto request = CloseRequest();

    quantara::BitunixManagementOnlyExchangePort confirmed(
        root, AckTransport, ClosedTruthTransport);
    ok &= Expect(confirmed.SubmitMutation(request) ==
                     quantara::ExistingPositionMutationSubmitOutcome::kAcknowledged,
                 "Allowlisted close must return acknowledged after HTTP 200.");
    ok &= Expect(confirmed.ConfirmMutation(request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kConfirmedByFreshExchangeTruth,
                 "Close must be confirmed only after fresh truth has no target position or order.");

    quantara::BitunixManagementOnlyExchangePort still_open(
        root, AckTransport, StillOpenTruthTransport);
    ok &= Expect(still_open.ConfirmMutation(request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kNotConfirmedByFreshExchangeTruth,
                 "A position still present in fresh truth must not be confirmed closed.");

    quantara::BitunixManagementOnlyExchangePort stale_order(
        root, AckTransport, StaleOrderTruthTransport);
    ok &= Expect(stale_order.ConfirmMutation(request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kNotConfirmedByFreshExchangeTruth,
                 "Residual target orders must keep close confirmation fail-closed.");

    quantara::BitunixManagementOnlyExchangePort ambiguous(
        root, AmbiguousTransport, ClosedTruthTransport);
    ok &= Expect(ambiguous.SubmitMutation(request) ==
                     quantara::ExistingPositionMutationSubmitOutcome::kOutcomeAmbiguous,
                 "A missing mutation response after transport entry must be treated as ambiguous.");
    ok &= Expect(ambiguous.ConfirmMutation(request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kConfirmedByFreshExchangeTruth,
                 "Ambiguous submit may complete only when fresh exchange truth proves closure.");

    const auto tighten_request = TightenStopRequest();
    quantara::BitunixManagementOnlyExchangePort tightened(
        root, AckTransport, TightenedStopTruthTransport);
    ok &= Expect(tightened.SubmitMutation(tighten_request) ==
                     quantara::ExistingPositionMutationSubmitOutcome::kAcknowledged,
                 "Allowlisted stop tightening must use the atomic Bitunix position TP/SL modify endpoint.");
    ok &= Expect(tightened.ConfirmMutation(tighten_request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kConfirmedByFreshExchangeTruth,
                 "Stop tightening must be confirmed only when the same live position has the requested exchange SL and trigger semantics.");

    quantara::BitunixManagementOnlyExchangePort wrong_trigger(
        root, AckTransport, WrongTriggerTruthTransport);
    ok &= Expect(wrong_trigger.ConfirmMutation(tighten_request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kNotConfirmedByFreshExchangeTruth,
                 "A trigger-type drift must not confirm stop tightening even when price matches.");

    quantara::BitunixManagementOnlyExchangePort wrong_stop(
        root, AckTransport, WrongStopTruthTransport);
    ok &= Expect(wrong_stop.ConfirmMutation(tighten_request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kNotConfirmedByFreshExchangeTruth,
                 "A stale or wrong exchange SL must not confirm stop tightening.");

    quantara::BitunixManagementOnlyExchangePort duplicate_stop(
        root, AckTransport, DuplicateStopTruthTransport);
    ok &= Expect(duplicate_stop.ConfirmMutation(tighten_request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kNotConfirmedByFreshExchangeTruth,
                 "Ambiguous duplicate exchange SL evidence must remain fail-closed.");

    auto invalid_stop = tighten_request;
    invalid_stop.new_stop_price = 0.0;
    ok &= Expect(tightened.SubmitMutation(invalid_stop) ==
                     quantara::ExistingPositionMutationSubmitOutcome::
                         kDefinitelyNotSubmitted,
                 "Invalid stop price must fail before mutation transport.");
    ok &= Expect(tightened.ConfirmMutation(invalid_stop) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kExchangeTruthUnavailable,
                 "Invalid expected stop evidence must fail before exchange confirmation.");

    auto missing_trigger = tighten_request;
    missing_trigger.stop_trigger_type = {};
    ok &= Expect(tightened.SubmitMutation(missing_trigger) ==
                     quantara::ExistingPositionMutationSubmitOutcome::
                         kDefinitelyNotSubmitted,
                 "Missing stop trigger semantics must fail before mutation transport.");
    ok &= Expect(tightened.ConfirmMutation(missing_trigger) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kExchangeTruthUnavailable,
                 "Missing requested trigger semantics must fail before exchange confirmation.");

    auto unsafe = request;
    unsafe.increases_exposure = true;
    ok &= Expect(confirmed.SubmitMutation(unsafe) ==
                     quantara::ExistingPositionMutationSubmitOutcome::
                         kDefinitelyNotSubmitted,
                 "Unsafe mutation must be rejected before network submission.");

    auto widening = tighten_request;
    widening.widens_stop = true;
    ok &= Expect(tightened.SubmitMutation(widening) ==
                     quantara::ExistingPositionMutationSubmitOutcome::
                         kDefinitelyNotSubmitted,
                 "Stop widening must remain impossible at the Bitunix request boundary.");

    quantara::BitunixManagementOnlyExchangePort missing_mutation_transport(
        root, nullptr, ClosedTruthTransport);
    ok &= Expect(missing_mutation_transport.SubmitMutation(request) ==
                     quantara::ExistingPositionMutationSubmitOutcome::
                         kDefinitelyNotSubmitted,
                 "Missing mutation transport must fail before submission.");

    quantara::BitunixManagementOnlyExchangePort missing_truth_transport(
        root, AckTransport, nullptr);
    ok &= Expect(missing_truth_transport.ConfirmMutation(request) ==
                     quantara::ExistingPositionMutationConfirmation::
                         kExchangeTruthUnavailable,
                 "Missing fresh-truth transport must never confirm mutation success.");
  } catch (...) {
    ok = false;
    std::cerr << "Management-only exchange port test raised an unexpected exception.\n";
  }

  std::filesystem::remove_all(root, ignored);
  return ok ? 0 : 1;
}
