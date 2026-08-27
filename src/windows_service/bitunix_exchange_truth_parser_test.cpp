#include "bitunix_exchange_truth_parser.h"

#include <iostream>
#include <string>

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

}  // namespace

int main() {
  bool ok = true;

  const std::string positions = R"json({
    "code":0,
    "data":[{
      "positionId":"12345678",
      "symbol":"BTCUSDT",
      "qty":"0.5",
      "entryValue":"30000",
      "side":"LONG",
      "positionMode":"HEDGE",
      "marginMode":"ISOLATION",
      "leverage":100,
      "fee":"0.1",
      "funding":"-0.2",
      "realizedPNL":"102.9",
      "margin":"300",
      "unrealizedPNL":"1.5",
      "liqPrice":"22209",
      "marginRate":"0.01",
      "avgOpenPrice":"1.0",
      "ctime":1691382137448,
      "mtime":1691382137448
    }],
    "msg":"Success"
  })json";

  const auto parsed_positions = quantara::ParseBitunixPendingPositionsResponse(positions);
  ok &= Expect(parsed_positions.has_value(), "documented pending-position response must parse");
  if (parsed_positions.has_value()) {
    ok &= Expect(parsed_positions->size() == 1, "one pending position expected");
    if (!parsed_positions->empty()) {
      const auto& position = parsed_positions->front();
      ok &= Expect(position.position_id == "12345678", "position id mismatch");
      ok &= Expect(position.symbol == "BTCUSDT", "position symbol mismatch");
      ok &= Expect(position.margin_mode == "ISOLATION", "margin mode mismatch");
      ok &= Expect(position.leverage == 100, "leverage mismatch");
    }
  }

  const std::string orders = R"json({
    "code":0,
    "data":{
      "orderList":[{
        "orderId":"11111",
        "qty":"1",
        "tradeQty":"0.5",
        "price":"60000",
        "symbol":"BTCUSDT",
        "positionMode":"HEDGE",
        "marginMode":"ISOLATION",
        "leverage":15,
        "status":"NEW",
        "fee":"0.01",
        "realizedPNL":"1.78",
        "type":"LIMIT",
        "effect":"GTC",
        "reduceOnly":true,
        "clientId":"quantara-22222",
        "tpPrice":"61000",
        "slPrice":"59000",
        "ctime":1597026383085,
        "mtime":1597026383085
      }],
      "total":1
    },
    "msg":"Success"
  })json";

  const auto parsed_orders = quantara::ParseBitunixPendingOrdersResponse(orders);
  ok &= Expect(parsed_orders.has_value(), "documented pending-order response must parse");
  if (parsed_orders.has_value()) {
    ok &= Expect(parsed_orders->total == 1, "pending-order total mismatch");
    ok &= Expect(parsed_orders->orders.size() == 1, "one pending order expected");
    if (!parsed_orders->orders.empty()) {
      const auto& order = parsed_orders->orders.front();
      ok &= Expect(order.order_id == "11111", "order id mismatch");
      ok &= Expect(order.client_id == "quantara-22222", "client id mismatch");
      ok &= Expect(order.reduce_only, "reduce-only flag must be preserved");
      ok &= Expect(order.take_profit_price == "61000", "take-profit mismatch");
      ok &= Expect(order.stop_loss_price == "59000", "stop-loss mismatch");
    }
  }

  ok &= Expect(
      !quantara::ParseBitunixPendingPositionsResponse(
           R"json({"code":10001,"data":[],"msg":"error"})json")
           .has_value(),
      "non-zero exchange code must fail closed");
  ok &= Expect(
      !quantara::ParseBitunixPendingPositionsResponse(
           R"json({"code":0,"data":[{"positionId":"1","symbol":"BTCUSDT","qty":"1","side":"LONG","positionMode":"HEDGE","marginMode":"CROSS","leverage":10,"leverage":11}]})json")
           .has_value(),
      "duplicate required fields must fail closed");
  ok &= Expect(
      !quantara::ParseBitunixPendingPositionsResponse(
           R"json({"code":0,"data":[{"positionId":"1","symbol":"BTCUSDT","qty":"1","side":"SIDEWAYS","positionMode":"HEDGE","marginMode":"ISOLATION","leverage":10}]})json")
           .has_value(),
      "unknown position side must fail closed");
  ok &= Expect(
      !quantara::ParseBitunixPendingOrdersResponse(
           R"json({"code":0,"data":{"orderList":[{"orderId":"1","symbol":"BTCUSDT","status":"FILLED","reduceOnly":true}],"total":1}})json")
           .has_value(),
      "non-pending order state must fail closed");
  ok &= Expect(
      !quantara::ParseBitunixPendingOrdersResponse(
           R"json({"code":0,"data":{"orderList":[{"orderId":"1","symbol":"BTCUSDT","status":"NEW","reduceOnly":"true"}],"total":1}})json")
           .has_value(),
      "type mismatch must fail closed");
  ok &= Expect(
      !quantara::ParseBitunixPendingOrdersResponse(
           R"json({"code":0,"data":{"orderList":[{"orderId":"1","symbol":"BTCUSDT","status":"NEW","reduceOnly":true}],"total":0}})json")
           .has_value(),
      "reported total smaller than parsed list must fail closed");
  ok &= Expect(
      !quantara::ParseBitunixPendingPositionsResponse("<html>proxy error</html>").has_value(),
      "non-JSON body must fail closed");

  if (!ok) return 1;
  std::cout << "Bitunix exchange truth parser self-test passed\n";
  return 0;
}
