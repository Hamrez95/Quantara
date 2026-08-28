#include "bitunix_https_readonly_transport.h"
#include "bitunix_exchange_truth_parser.h"

// Keep the parser compiled by the existing bounded Bitunix transport gate until
// the next adapter slice wires it into the Windows service executable.
#include "bitunix_exchange_truth_parser.cpp"

#include <iostream>
#include <limits>
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

bool TestExchangeTruthParser() {
  bool ok = true;
  const std::string positions = R"json({"code":0,"data":[{"positionId":"12345678","symbol":"BTCUSDT","qty":"0.5","entryValue":"30000","side":"LONG","positionMode":"HEDGE","marginMode":"ISOLATION","leverage":100,"fee":"0.1","funding":"-0.2","realizedPNL":"102.9","margin":"300","unrealizedPNL":"1.5","liqPrice":"22209","marginRate":"0.01","avgOpenPrice":"1.0","ctime":1691382137448,"mtime":1691382137448}],"msg":"Success"})json";
  const auto parsed_positions = quantara::ParseBitunixPendingPositionsResponse(positions);
  ok &= Expect(parsed_positions.has_value(), "Documented pending-position response must parse.");
  if (parsed_positions.has_value()) {
    ok &= Expect(parsed_positions->size() == 1, "One pending position expected.");
    if (!parsed_positions->empty()) {
      const auto& position = parsed_positions->front();
      ok &= Expect(position.position_id == "12345678", "Position id mismatch.");
      ok &= Expect(position.symbol == "BTCUSDT", "Position symbol mismatch.");
      ok &= Expect(position.margin_mode == "ISOLATION", "Margin mode mismatch.");
      ok &= Expect(position.leverage == 100, "Leverage mismatch.");
    }
  }

  const std::string orders = R"json({"code":0,"data":{"orderList":[{"orderId":"11111","qty":"1","tradeQty":"0.5","price":"60000","symbol":"BTCUSDT","positionMode":"HEDGE","marginMode":"ISOLATION","leverage":15,"status":"NEW","fee":"0.01","realizedPNL":"1.78","type":"LIMIT","effect":"GTC","reduceOnly":true,"clientId":"quantara-22222","tpPrice":"61000","slPrice":"59000","ctime":1597026383085,"mtime":1597026383085}],"total":1},"msg":"Success"})json";
  const auto parsed_orders = quantara::ParseBitunixPendingOrdersResponse(orders);
  ok &= Expect(parsed_orders.has_value(), "Documented pending-order response must parse.");
  if (parsed_orders.has_value()) {
    ok &= Expect(parsed_orders->total == 1, "Pending-order total mismatch.");
    ok &= Expect(parsed_orders->orders.size() == 1, "One pending order expected.");
    if (!parsed_orders->orders.empty()) {
      const auto& order = parsed_orders->orders.front();
      ok &= Expect(order.order_id == "11111", "Order id mismatch.");
      ok &= Expect(order.client_id == "quantara-22222", "Client id mismatch.");
      ok &= Expect(order.reduce_only, "Reduce-only flag must be preserved.");
      ok &= Expect(order.take_profit_price == "61000", "Take-profit mismatch.");
      ok &= Expect(order.stop_loss_price == "59000", "Stop-loss mismatch.");
    }
  }

  ok &= Expect(!quantara::ParseBitunixPendingPositionsResponse(
                    R"json({"code":10001,"data":[],"msg":"error"})json")
                    .has_value(),
               "Non-zero exchange code must fail closed.");
  ok &= Expect(!quantara::ParseBitunixPendingPositionsResponse(
                    R"json({"code":0,"data":[{"positionId":"1","symbol":"BTCUSDT","qty":"1","side":"LONG","positionMode":"HEDGE","marginMode":"ISOLATION","leverage":10,"leverage":11}]})json")
                    .has_value(),
               "Duplicate required fields must fail closed.");
  ok &= Expect(!quantara::ParseBitunixPendingPositionsResponse(
                    R"json({"code":0,"data":[{"positionId":"1","symbol":"BTCUSDT","qty":"1","side":"SIDEWAYS","positionMode":"HEDGE","marginMode":"ISOLATION","leverage":10}]})json")
                    .has_value(),
               "Unknown position side must fail closed.");
  ok &= Expect(!quantara::ParseBitunixPendingOrdersResponse(
                    R"json({"code":0,"data":{"orderList":[{"orderId":"1","symbol":"BTCUSDT","status":"FILLED","reduceOnly":true}],"total":1}})json")
                    .has_value(),
               "Non-pending order state must fail closed.");
  ok &= Expect(!quantara::ParseBitunixPendingOrdersResponse(
                    R"json({"code":0,"data":{"orderList":[{"orderId":"1","symbol":"BTCUSDT","status":"NEW","reduceOnly":"true"}],"total":1}})json")
                    .has_value(),
               "Type mismatch must fail closed.");
  ok &= Expect(!quantara::ParseBitunixPendingOrdersResponse(
                    R"json({"code":0,"data":{"orderList":[{"orderId":"1","symbol":"BTCUSDT","status":"NEW","reduceOnly":true}],"total":0}})json")
                    .has_value(),
               "Reported total smaller than parsed list must fail closed.");
  ok &= Expect(!quantara::ParseBitunixPendingPositionsResponse("<html>proxy error</html>").has_value(),
               "Non-JSON body must fail closed.");
  return ok;
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
  mutated.resource = "/api/v1/futures/position/get_pending_positions?evil=BTCUSDT";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Unknown query keys must fail closed at the transport boundary.");

  mutated = valid;
  mutated.resource = "/api/v1/futures/position/get_pending_positions?symbol=BTCUSDT&symbol=ETHUSDT";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Duplicate query keys must fail closed at the transport boundary.");

  mutated = valid;
  mutated.resource = "/api/v1/futures/position/get_pending_positions?symbol=BTC%2GUSDT";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Malformed percent encoding must fail closed.");

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

  mutated = valid;
  mutated.headers[2].second = "not-a-timestamp";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Malformed timestamps must fail closed.");

  mutated = valid;
  mutated.headers[3].second = "not-a-signature";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Malformed signatures must fail closed.");

  mutated = valid;
  mutated.headers[4].second = "text/plain";
  ok &= Expect(!quantara::ValidateBitunixHttpsReadOnlyEnvelope(mutated),
               "Content type mutation must fail closed.");

  quantara::BitunixHttpsReadOnlyLimits invalid_limits;
  invalid_limits.max_body_bytes = 0;
  ok &= Expect(!quantara::ExecuteBitunixHttpsReadOnly(valid, invalid_limits).has_value(),
               "Zero response body bound must fail before network I/O.");

  invalid_limits = {};
  invalid_limits.receive_timeout_ms = 0;
  ok &= Expect(!quantara::ExecuteBitunixHttpsReadOnly(valid, invalid_limits).has_value(),
               "Zero receive timeout must fail before network I/O.");

  invalid_limits = {};
  invalid_limits.connect_timeout_ms =
      static_cast<unsigned long>((std::numeric_limits<int>::max)()) + 1UL;
  ok &= Expect(!quantara::ExecuteBitunixHttpsReadOnly(valid, invalid_limits).has_value(),
               "Timeouts that cannot be represented by WinHTTP must fail before I/O.");

  ok &= TestExchangeTruthParser();

  if (!ok) return 1;
  std::cout << "Bitunix HTTPS transport and exchange-truth parser tests passed.\n";
  return 0;
}
