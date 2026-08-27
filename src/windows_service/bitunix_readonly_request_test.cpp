#include "bitunix_readonly_request.h"

#include <windows.h>

#include <algorithm>
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

std::string HeaderValue(
    const quantara::BitunixReadOnlyHttpEnvelope& envelope,
    const std::string& name) {
  const auto it = std::find_if(
      envelope.headers.begin(), envelope.headers.end(),
      [&](const auto& header) { return header.first == name; });
  return it == envelope.headers.end() ? std::string{} : it->second;
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

      const auto envelope = quantara::BuildBitunixReadOnlyHttpEnvelope(*positions);
      ok &= Expect(envelope.has_value(),
                   "Valid read request must produce an HTTP envelope.");
      if (envelope.has_value()) {
        ok &= Expect(envelope->host == "fapi.bitunix.com",
                     "HTTP envelope must keep the pinned futures host.");
        ok &= Expect(envelope->method == "GET",
                     "HTTP envelope must remain GET-only.");
        ok &= Expect(
            envelope->resource ==
                "/api/v1/futures/position/get_pending_positions?symbol=BTCUSDT",
            "HTTP resource must encode the allowlisted query deterministically.");
        ok &= Expect(HeaderValue(*envelope, "api-key") == "demo-api",
                     "HTTP envelope must contain the API key header.");
        ok &= Expect(HeaderValue(*envelope, "nonce") == nonce,
                     "HTTP envelope must contain the nonce header.");
        ok &= Expect(HeaderValue(*envelope, "timestamp") == timestamp,
                     "HTTP envelope must contain the timestamp header.");
        ok &= Expect(HeaderValue(*envelope, "sign").size() == 64,
                     "HTTP envelope must contain the SHA-256 signature header.");
        ok &= Expect(HeaderValue(*envelope, "Content-Type") == "application/json",
                     "HTTP envelope must pin JSON content type.");
        ok &= Expect(HeaderValue(*envelope, "digest").empty(),
                     "Internal signing digest must never become a transport header.");
        ok &= Expect(envelope->headers.size() == 5,
                     "HTTP envelope must expose only the required authentication headers.");
      }

      auto mutated = *positions;
      mutated.method = "POST";
      ok &= Expect(!quantara::BuildBitunixReadOnlyHttpEnvelope(mutated).has_value(),
                   "Mutating GET to POST must fail closed.");

      mutated = *positions;
      mutated.host = "example.com";
      ok &= Expect(!quantara::BuildBitunixReadOnlyHttpEnvelope(mutated).has_value(),
                   "Changing the pinned exchange host must fail closed.");

      mutated = *positions;
      mutated.path = "/api/v1/futures/trade/cancel_all_orders";
      ok &= Expect(!quantara::BuildBitunixReadOnlyHttpEnvelope(mutated).has_value(),
                   "Mutating the path to a trading endpoint must fail closed.");

      mutated = *positions;
      mutated.authorization.api_key = "demo-api\r\nX-Evil: injected";
      ok &= Expect(!quantara::BuildBitunixReadOnlyHttpEnvelope(mutated).has_value(),
                   "Header injection must fail closed.");

      mutated = *positions;
      mutated.authorization.timestamp = "not-a-timestamp";
      ok &= Expect(!quantara::BuildBitunixReadOnlyHttpEnvelope(mutated).has_value(),
                   "Non-decimal timestamps must fail closed.");

      mutated = *positions;
      mutated.authorization.sign = "not-a-signature";
      ok &= Expect(!quantara::BuildBitunixReadOnlyHttpEnvelope(mutated).has_value(),
                   "Malformed signatures must fail closed.");
    }

    const auto orders = quantara::BuildBitunixReadOnlyRequest(
        root, quantara::BitunixReadOnlyEndpoint::kPendingOrders, nonce,
        timestamp, {{"symbol", "BTC/USDT"}, {"limit", "100"}, {"skip", "0"}});
    ok &= Expect(orders.has_value(), "Pending orders read must be authorizable.");
    if (orders.has_value()) {
      ok &= Expect(
          orders->path == "/api/v1/futures/trade/get_pending_orders",
          "Pending orders path must match the official Bitunix API.");
      const auto envelope = quantara::BuildBitunixReadOnlyHttpEnvelope(*orders);
      ok &= Expect(envelope.has_value(),
                   "Pending orders request must produce an HTTP envelope.");
      if (envelope.has_value()) {
        ok &= Expect(
            envelope->resource.find("symbol=BTC%2FUSDT") != std::string::npos,
            "Reserved query characters must be percent-encoded before transport.");
      }
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
