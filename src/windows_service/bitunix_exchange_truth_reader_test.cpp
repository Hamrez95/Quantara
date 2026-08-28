#include "bitunix_exchange_truth_reader.h"

#include <windows.h>

#include <filesystem>
#include <iostream>
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
         (L"quantara-bitunix-truth-reader-" +
          std::to_wstring(GetCurrentProcessId()));
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> GoodTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  if (envelope.resource.find("/position/get_pending_positions") !=
      std::string::npos) {
    return quantara::BitunixHttpsReadOnlyResponse{
        200,
        R"json({"code":0,"data":[{"positionId":"pos-1","symbol":"BTCUSDT","qty":"0.001","side":"LONG","marginMode":"ISOLATION","positionMode":"ONE_WAY","leverage":5}]})json"};
  }
  if (envelope.resource ==
      "/api/v1/futures/trade/get_pending_orders?limit=100&skip=0") {
    return quantara::BitunixHttpsReadOnlyResponse{
        200,
        R"json({"code":0,"data":{"orderList":[{"orderId":"order-1","positionId":"pos-1","symbol":"BTCUSDT","status":"NEW","reduceOnly":true,"tpPrice":"70000","slPrice":"60000"}],"total":1}})json"};
  }
  return std::nullopt;
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> PartialOrdersTransport(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const quantara::BitunixHttpsReadOnlyLimits& limits) noexcept {
  const auto response = GoodTransport(envelope, limits);
  if (!response.has_value() ||
      envelope.resource.find("/trade/get_pending_orders") == std::string::npos) {
    return response;
  }
  return quantara::BitunixHttpsReadOnlyResponse{
      200,
      R"json({"code":0,"data":{"orderList":[{"orderId":"order-1","positionId":"pos-1","symbol":"BTCUSDT","status":"NEW","reduceOnly":true}],"total":2}})json"};
}

std::optional<quantara::BitunixHttpsReadOnlyResponse> BadStatusTransport(
    const quantara::BitunixReadOnlyHttpEnvelope&,
    const quantara::BitunixHttpsReadOnlyLimits&) noexcept {
  return quantara::BitunixHttpsReadOnlyResponse{503, "{}"};
}

}  // namespace

int main() {
  bool ok = true;
  const auto root = TestRoot();
  ok &= Expect(!root.empty(), "Temporary credential root must be available.");
  if (root.empty()) return 1;

  std::error_code ignored;
  std::filesystem::remove_all(root, ignored);

  const quantara::BitunixReadOnlyAuthStamp positions_auth{
      "00112233445566778899aabbccddeeff", "1767225600123"};
  const quantara::BitunixReadOnlyAuthStamp orders_auth{
      "ffeeddccbbaa99887766554433221100", "1767225600124"};

  ok &= Expect(!quantara::ReadBitunixExchangeTruth(
                    root, positions_auth, orders_auth, GoodTransport)
                    .has_value(),
               "Missing protected credentials must fail closed.");

  try {
    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-api-key", "demo-api");
    vault.Store(L"bitunix-api-secret", "demo-secret");

    const auto snapshot = quantara::ReadBitunixExchangeTruth(
        root, positions_auth, orders_auth, GoodTransport);
    ok &= Expect(snapshot.has_value() && snapshot->positions.size() == 1 &&
                     snapshot->pending_orders.orders.size() == 1 &&
                     snapshot->pending_orders.total == 1,
                 "Complete read-only exchange truth must compose atomically.");

    ok &= Expect(!quantara::ReadBitunixExchangeTruth(
                      root, positions_auth, positions_auth, GoodTransport)
                      .has_value(),
                 "Reusing a nonce across private reads must fail closed.");

    ok &= Expect(!quantara::ReadBitunixExchangeTruth(
                      root, positions_auth, orders_auth,
                      PartialOrdersTransport)
                      .has_value(),
                 "A partial pending-order page must never be accepted as complete truth.");

    ok &= Expect(!quantara::ReadBitunixExchangeTruth(
                      root, positions_auth, orders_auth, BadStatusTransport)
                      .has_value(),
                 "Non-200 transport responses must fail closed.");

    ok &= Expect(!quantara::ReadBitunixExchangeTruth(
                      root, positions_auth, orders_auth, nullptr)
                      .has_value(),
                 "A missing transport boundary must fail closed.");
  } catch (...) {
    ok = false;
    std::cerr << "Exchange-truth reader test raised an unexpected exception.\n";
  }

  std::filesystem::remove_all(root, ignored);
  return ok ? 0 : 1;
}
