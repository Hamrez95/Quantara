#include "bitunix_management_only_https_transport.h"

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
         (L"quantara-bitunix-management-https-" +
          std::to_wstring(GetCurrentProcessId()));
}

quantara::BitunixManagementOnlyHttpRequest SafeClose() {
  return quantara::BitunixManagementOnlyHttpRequest{
      "POST", "/api/v1/futures/trade/flash_close_position",
      "{\"positionId\":\"123456789\"}"};
}

quantara::BitunixManagementOnlyHttpRequest SafeTighten() {
  return quantara::BitunixManagementOnlyHttpRequest{
      "POST", "/api/v1/futures/tpsl/position/modify_order",
      "{\"symbol\":\"BTCUSDT\",\"positionId\":\"123456789\",\"slPrice\":\"65000\",\"slStopType\":\"MARK_PRICE\"}"};
}

}  // namespace

int main() {
  bool ok = true;
  const auto root = TestRoot();
  ok &= Expect(!root.empty(), "Temporary credential root must be available.");
  if (root.empty()) return 1;

  std::error_code ignored;
  std::filesystem::remove_all(root, ignored);

  const auto close = SafeClose();
  const auto tighten = SafeTighten();
  ok &= Expect(
      !quantara::BuildBitunixManagementOnlyHttpEnvelope(
           root, close, "00112233445566778899aabbccddeeff", "1767225600123")
           .has_value(),
      "Missing protected credentials must fail closed before transport.");
  ok &= Expect(
      !quantara::BuildBitunixManagementOnlyHttpEnvelope(
           root, tighten, "00112233445566778899aabbccddeeff",
           "1767225600123")
           .has_value(),
      "Missing protected credentials must also block stop tightening.");

  try {
    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-api-key", "demo-api");
    vault.Store(L"bitunix-api-secret", "demo-secret");

    const auto envelope = quantara::BuildBitunixManagementOnlyHttpEnvelope(
        root, close, "00112233445566778899aabbccddeeff", "1767225600123");
    ok &= Expect(envelope.has_value(),
                 "Verified close request must produce an authenticated envelope.");
    if (envelope.has_value()) {
      ok &= Expect(envelope->host == "fapi.bitunix.com" &&
                       envelope->method == "POST" &&
                       envelope->resource ==
                           "/api/v1/futures/trade/flash_close_position" &&
                       envelope->body == "{\"positionId\":\"123456789\"}",
                   "Envelope must remain pinned to the exact close endpoint/body.");
      ok &= Expect(envelope->headers.size() == 5,
                   "Envelope must expose exactly the required auth headers.");
      ok &= Expect(
          !quantara::ExecuteBitunixManagementOnlyHttps(
               quantara::BitunixManagementOnlyHttpEnvelope{
                   envelope->host, "GET", envelope->resource, envelope->body,
                   envelope->headers})
               .has_value(),
          "Transport must reject method mutation before network I/O.");
      ok &= Expect(
          !quantara::ExecuteBitunixManagementOnlyHttps(
               quantara::BitunixManagementOnlyHttpEnvelope{
                   envelope->host, envelope->method,
                   "/api/v1/futures/trade/place_order", envelope->body,
                   envelope->headers})
               .has_value(),
          "Transport must reject generic order endpoints before network I/O.");
      ok &= Expect(
          !quantara::ExecuteBitunixManagementOnlyHttps(
               quantara::BitunixManagementOnlyHttpEnvelope{
                   envelope->host, envelope->method, envelope->resource,
                   "{\"positionId\":\"123\",\"qty\":\"1\"}",
                   envelope->headers})
               .has_value(),
          "Transport must reject body expansion beyond positionId-only close.");
      auto duplicate_headers = envelope->headers;
      duplicate_headers.push_back({"sign", std::string(64, 'a')});
      ok &= Expect(
          !quantara::ExecuteBitunixManagementOnlyHttps(
               quantara::BitunixManagementOnlyHttpEnvelope{
                   envelope->host, envelope->method, envelope->resource,
                   envelope->body, duplicate_headers})
               .has_value(),
          "Duplicate authorization headers must fail closed.");
    }

    const auto tighten_envelope =
        quantara::BuildBitunixManagementOnlyHttpEnvelope(
            root, tighten, "00112233445566778899aabbccddeeff",
            "1767225600123");
    ok &= Expect(
        tighten_envelope.has_value(),
        "Canonical atomic stop tightening must produce an authenticated envelope.");
    if (tighten_envelope.has_value()) {
      ok &= Expect(
          tighten_envelope->host == "fapi.bitunix.com" &&
              tighten_envelope->method == "POST" &&
              tighten_envelope->resource ==
                  "/api/v1/futures/tpsl/position/modify_order" &&
              tighten_envelope->body == tighten.body,
          "Stop-tightening envelope must remain pinned to the atomic TP/SL modify endpoint and canonical body.");

      auto widened_shape = tighten_envelope->body;
      widened_shape.insert(widened_shape.size() - 1, ",\"qty\":\"1\"");
      ok &= Expect(
          !quantara::ExecuteBitunixManagementOnlyHttps(
               quantara::BitunixManagementOnlyHttpEnvelope{
                   tighten_envelope->host, tighten_envelope->method,
                   tighten_envelope->resource, widened_shape,
                   tighten_envelope->headers})
               .has_value(),
          "Transport must reject extra fields on the atomic stop-tightening body.");
    }

    auto wrong_method = close;
    wrong_method.method = "GET";
    ok &= Expect(
        !quantara::BuildBitunixManagementOnlyHttpEnvelope(
             root, wrong_method, "00112233445566778899aabbccddeeff",
             "1767225600123")
             .has_value(),
        "Builder must reject non-POST management requests.");

    auto unsafe_body = close;
    unsafe_body.body = "{\"positionId\":\"123\",\"symbol\":\"BTCUSDT\"}";
    ok &= Expect(
        !quantara::BuildBitunixManagementOnlyHttpEnvelope(
             root, unsafe_body, "00112233445566778899aabbccddeeff",
             "1767225600123")
             .has_value(),
        "Builder must reject body fields outside the allowlisted close contract.");

    auto unsafe_id = close;
    unsafe_id.body = "{\"positionId\":\"123\\\"x\"}";
    ok &= Expect(
        !quantara::BuildBitunixManagementOnlyHttpEnvelope(
             root, unsafe_id, "00112233445566778899aabbccddeeff",
             "1767225600123")
             .has_value(),
        "Builder must reject non-decimal or escaped position identifiers.");

    auto unsafe_tighten = tighten;
    unsafe_tighten.body =
        "{\"symbol\":\"BTCUSDT\",\"positionId\":\"123456789\",\"slPrice\":\"65000\",\"slStopType\":\"INDEX_PRICE\"}";
    ok &= Expect(
        !quantara::BuildBitunixManagementOnlyHttpEnvelope(
             root, unsafe_tighten, "00112233445566778899aabbccddeeff",
             "1767225600123")
             .has_value(),
        "Unknown stop trigger semantics must fail closed before network transport.");

    auto non_positive_tighten = tighten;
    non_positive_tighten.body =
        "{\"symbol\":\"BTCUSDT\",\"positionId\":\"123456789\",\"slPrice\":\"0\",\"slStopType\":\"MARK_PRICE\"}";
    ok &= Expect(
        !quantara::BuildBitunixManagementOnlyHttpEnvelope(
             root, non_positive_tighten,
             "00112233445566778899aabbccddeeff", "1767225600123")
             .has_value(),
        "Non-positive stop prices must fail closed before network transport.");

    ok &= Expect(
        !quantara::BuildBitunixManagementOnlyHttpEnvelope(
             root, close, "", "1767225600123")
             .has_value(),
        "Empty nonce must fail closed.");
  } catch (...) {
    ok = false;
    std::cerr << "Management HTTPS transport test raised an unexpected exception.\n";
  }

  std::filesystem::remove_all(root, ignored);
  return ok ? 0 : 1;
}
