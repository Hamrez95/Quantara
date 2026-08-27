#include "bitunix_readonly_request.h"

#include <windows.h>

#include <filesystem>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

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
         (L"quantara-bitunix-readonly-request-" +
          std::to_wstring(GetCurrentProcessId()));
}

}  // namespace

int main() {
  bool ok = true;
  const auto root = TestRoot();
  ok &= Expect(!root.empty(), "Temporary credential root must be available.");
  if (root.empty()) return 1;

  std::error_code ignored;
  std::filesystem::remove_all(root, ignored);

  const auto nonce = "00112233445566778899aabbccddeeff";
  const auto timestamp = "1767225600123";

  ok &= Expect(
      !quantara::BuildBitunixReadOnlyRequest(
           root, quantara::BitunixReadOnlyEndpoint::kPendingPositions, nonce,
           timestamp, {{"symbol", "BTCUSDT"}})
           .has_value(),
      "Missing protected credentials must fail closed.");

  try {
    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-api-key", "demo-api");
    vault.Store(L"bitunix-api-secret", "demo-secret");

    const auto positions = quantara::BuildBitunixReadOnlyRequest(
        root, quantara::BitunixReadOnlyEndpoint::kPendingPositions, nonce,
        timestamp, {{"symbol", "BTCUSDT"}});
    ok &= Expect(positions.has_value(),
                 "Pending positions read must be authorizable.");
    if (positions.has_value()) {
      ok &= Expect(positions->host == "fapi.bitunix.com",
                   "Private truth host must be pinned to Bitunix futures API.");
      ok &= Expect(positions->method == "GET",
                   "Exchange truth contract must remain GET-only.");
      ok &= Expect(
          positions->path ==
              "/api/v1/futures/position/get_pending_positions",
          "Pending positions path must match the official Bitunix API.");
      ok &= Expect(positions->authorization.api_key == "demo-api",
                   "Request must carry the protected API key header value.");
    }

    const auto orders = quantara::BuildBitunixReadOnlyRequest(
        root, quantara::BitunixReadOnlyEndpoint::kPendingOrders, nonce,
        timestamp, {{"symbol", "BTCUSDT"}, {"limit", "100"}, {"skip", "0"}});
    ok &= Expect(orders.has_value(), "Pending orders read must be authorizable.");
    if (orders.has_value()) {
      ok &= Expect(
          orders->path == "/api/v1/futures/trade/get_pending_orders",
          "Pending orders path must match the official Bitunix API.");
    }

    ok &= Expect(
        !quantara::BuildBitunixReadOnlyRequest(
             root, quantara::BitunixReadOnlyEndpoint::kPendingPositions, nonce,
             timestamp, {{"includeSubAccounts", "true"}})
             .has_value(),
        "Sub-account expansion must remain outside the minimal truth contract.");
    ok &= Expect(
        !quantara::BuildBitunixReadOnlyRequest(
             root, quantara::BitunixReadOnlyEndpoint::kPendingOrders, nonce,
             timestamp, {{"limit", "100"}, {"limit", "10"}})
             .has_value(),
        "Duplicate query keys must fail closed.");
    ok &= Expect(
        !quantara::BuildBitunixReadOnlyRequest(
             root, quantara::BitunixReadOnlyEndpoint::kPendingOrders, nonce,
             timestamp, {{"symbol", "BTCUSDT&status=FILLED"}})
             .has_value(),
        "Query delimiter injection must fail closed.");
    ok &= Expect(
        !quantara::BuildBitunixReadOnlyRequest(
             root, static_cast<quantara::BitunixReadOnlyEndpoint>(999), nonce,
             timestamp)
             .has_value(),
        "Unknown endpoint values must fail closed.");
  } catch (...) {
    ok = false;
    std::cerr << "Read-only request test raised an unexpected exception.\n";
  }

  std::filesystem::remove_all(root, ignored);
  return ok ? 0 : 1;
}
