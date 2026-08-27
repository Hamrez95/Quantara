#include "bitunix_https_readonly_transport.h"

#include <iostream>
#include <string>
#include <utility>
#include <vector>

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << "FAIL: " << message << '\n';
  return condition;
}

quantara::BitunixReadOnlyHttpEnvelope ValidEnvelope() {
  return {
      "fapi.bitunix.com",
      "GET",
      "/api/v1/futures/position/get_pending_positions?symbol=BTCUSDT",
      {{"api-key", "demo-api"},
       {"nonce", "1234567890"},
       {"timestamp", "1770000000000"},
       {"sign", std::string(64, 'a')},
       {"Content-Type", "application/json"}},
  };
}

}  // namespace

int main() {
  bool ok = true;

  const auto valid = ValidEnvelope();
  ok &= Expect(quantara::ValidateBitunixHttpsReadOnlyEnvelope(valid),
               "Canonical Bitunix read envelope must be accepted.");

  auto mutated = valid;
  mutated.host = "example.com";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Host mutation must fail closed.");

  mutated = valid;
  mutated.method = "POST";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Non-GET methods must fail closed.");

  mutated = valid;
  mutated.resource = "/api/v1/futures/trade/cancel_all_orders";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Trading endpoint substitution must fail closed.");

  mutated = valid;
  mutated.resource += "#fragment";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Fragments must fail closed.");

  mutated = valid;
  mutated.headers.pop_back();
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Missing required headers must fail closed.");

  mutated = valid;
  mutated.headers.emplace_back("api-key", "duplicate");
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Duplicate authentication headers must fail closed.");

  mutated = valid;
  mutated.headers[0].second = "demo\r\nX-Evil: injected";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Header injection must fail closed.");

  quantara::BitunixHttpsReadOnlyLimits invalid_limits;
  invalid_limits.max_body_bytes = 0;
  ok &= Expect(!quantara::ExecuteBitunixHttpsReadOnly(valid, invalid_limits).has_value(),
               "Zero response body bound must fail before network I/O.");

  invalid_limits = {};
  invalid_limits.receive_timeout_ms = 0;
  ok &= Expect(!quantara::ExecuteBitunixHttpsReadOnly(valid, invalid_limits).has_value(),
               "Zero receive timeout must fail before network I/O.");

  if (!ok) return 1;
  std::cout << "Bitunix HTTPS read-only transport boundary tests passed.\n";
  return 0;
}
