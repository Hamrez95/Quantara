#include "bitunix_exchange_truth_parser.h"

#include <iostream>
#include <string_view>

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

}  // namespace

int main() {
  bool ok = true;

  constexpr std::string_view kValidPositions = R"json(
    {
      "code": 0,
      "data": [
        {
          "positionId": "pos-1",
          "symbol": "BTCUSDT",
          "qty": "0.001",
          "side": "LONG",
          "marginMode": "ISOLATION",
          "positionMode": "ONE_WAY",
          "leverage": 5
        }
      ]
    }
  )json";
  const auto positions = quantara::ParseBitunixPendingPositionsResponse(kValidPositions);
  ok &= Expect(positions.has_value() && positions->size() == 1,
               "A documented pending-position envelope must parse.");
  if (positions.has_value() && positions->size() == 1) {
    const auto& position = positions->front();
    ok &= Expect(position.position_id == "pos-1" && position.symbol == "BTCUSDT" &&
                     position.side == "LONG" && position.margin_mode == "ISOLATION" &&
                     position.position_mode == "ONE_WAY" && position.quantity == "0.001" &&
                     position.leverage == 5,
                 "Parsed position facts must preserve the read-only exchange truth exactly.");
  }

  constexpr std::string_view kValidOrders = R"json(
    {
      "code": 0,
      "data": {
        "orderList": [
          {
            "orderId": "order-1",
            "clientId": "quantara-protection-1",
            "positionId": "pos-1",
            "symbol": "BTCUSDT",
            "status": "NEW",
            "reduceOnly": true,
            "tpPrice": "70000",
            "slPrice": "60000"
          }
        ],
        "total": 1
      }
    }
  )json";
  const auto orders = quantara::ParseBitunixPendingOrdersResponse(kValidOrders);
  ok &= Expect(orders.has_value() && orders->orders.size() == 1 && orders->total == 1,
               "A documented pending-order envelope must parse.");
  if (orders.has_value() && orders->orders.size() == 1) {
    const auto& order = orders->orders.front();
    ok &= Expect(order.order_id == "order-1" && order.position_id == "pos-1" &&
                     order.symbol == "BTCUSDT" && order.status == "NEW" &&
                     order.reduce_only && order.take_profit_price == "70000" &&
                     order.stop_loss_price == "60000",
                 "Parsed order facts must preserve protection metadata exactly.");
  }

  ok &= Expect(!quantara::ParseBitunixPendingPositionsResponse(
                    R"json({"code":10001,"data":[]})json")
                    .has_value(),
               "Non-zero Bitunix response codes must fail closed.");

  ok &= Expect(!quantara::ParseBitunixPendingPositionsResponse(
                    R"json({"code":0,"data":[{"positionId":"pos-1","positionId":"pos-2","symbol":"BTCUSDT","qty":"1","side":"LONG","marginMode":"ISOLATION","positionMode":"ONE_WAY","leverage":2}]})json")
                    .has_value(),
               "Duplicate required position fields must fail closed.");

  ok &= Expect(!quantara::ParseBitunixPendingPositionsResponse(
                    R"json({"code":0,"data":[{"positionId":"pos-1","symbol":"BTCUSDT","qty":"1","side":"SIDEWAYS","marginMode":"ISOLATION","positionMode":"ONE_WAY","leverage":2}]})json")
                    .has_value(),
               "Unknown exchange enums must fail closed.");

  ok &= Expect(!quantara::ParseBitunixPendingOrdersResponse(
                    R"json({"code":0,"data":{"orderList":[{"orderId":"order-1","symbol":"BTCUSDT","status":"NEW","reduceOnly":"true"}],"total":1}})json")
                    .has_value(),
               "Type mismatches in protection facts must fail closed.");

  ok &= Expect(!quantara::ParseBitunixPendingOrdersResponse(
                    R"json({"code":0,"data":{"orderList":[{"orderId":"order-1","symbol":"BTCUSDT","status":"NEW","reduceOnly":true}],"total":0}})json")
                    .has_value(),
               "Order totals smaller than the returned list must fail closed.");

  ok &= Expect(!quantara::ParseBitunixPendingOrdersResponse("{not-json").has_value(),
               "Malformed JSON must fail closed.");

  if (!ok) return 1;
  std::cout << "Bitunix exchange-truth parser tests passed.\n";
  return 0;
}
