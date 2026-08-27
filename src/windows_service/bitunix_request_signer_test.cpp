#include "bitunix_request_signer.h"

#include <iostream>
#include <string>
#include <utility>
#include <vector>

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

}  // namespace

int main() {
  bool ok = true;
  const std::vector<std::pair<std::string, std::string>> query = {
      {"symbol", "BTCUSDT"}, {"limit", "100"}, {"skip", "0"}};

  const auto signature = quantara::CreateBitunixRequestSignature(
      "00112233445566778899aabbccddeeff", "1767225600123", "demo-api",
      "demo-secret", query);
  ok &= Expect(signature.has_value(), "Signing must produce a digest.");
  if (signature.has_value()) {
    ok &= Expect(
        signature->digest ==
            "aeb2aa31ef1ad337b28c9e5fcd5ef14a3e7ac2819a387e2a8e0049412d65a9f7",
        "Digest must match the canonical Flutter Bitunix signer vector.");
    ok &= Expect(
        signature->sign ==
            "d9c126d885c800a82f88dbbfdd7f8870e1f1b987615d2d8c345ebbda1dc26f83",
        "Signature must match the canonical Flutter Bitunix signer vector.");
  }

  const auto reordered = quantara::CreateBitunixRequestSignature(
      "00112233445566778899aabbccddeeff", "1767225600123", "demo-api",
      "demo-secret",
      {{"skip", "0"}, {"symbol", "BTCUSDT"}, {"limit", "100"}});
  ok &= Expect(reordered.has_value() && signature.has_value() &&
                   reordered->digest == signature->digest &&
                   reordered->sign == signature->sign,
               "Query insertion order must not affect signing.");

  const auto wrong_secret = quantara::CreateBitunixRequestSignature(
      "00112233445566778899aabbccddeeff", "1767225600123", "demo-api",
      "other-secret", query);
  ok &= Expect(wrong_secret.has_value() && signature.has_value() &&
                   wrong_secret->digest == signature->digest &&
                   wrong_secret->sign != signature->sign,
               "Secret key may affect only the final signature stage.");

  const auto with_body = quantara::CreateBitunixRequestSignature(
      "00112233445566778899aabbccddeeff", "1767225600123", "demo-api",
      "demo-secret", {}, "{\"reduceOnly\":true}");
  ok &= Expect(with_body.has_value() && signature.has_value() &&
                   with_body->digest != signature->digest,
               "Request body must participate in the canonical digest.");

  return ok ? 0 : 1;
}
