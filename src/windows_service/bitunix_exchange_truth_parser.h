#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace quantara {

struct BitunixPendingPosition final {
  std::string position_id;
  std::string symbol;
  std::string side;
  std::string margin_mode;
  std::string position_mode;
  std::string quantity;
  int leverage = 0;
};

struct BitunixPendingOrder final {
  std::string order_id;
  std::string client_id;
  std::string position_id;
  std::string symbol;
  std::string status;
  bool reduce_only = false;
  std::string take_profit_price;
  std::string stop_loss_price;
};

struct BitunixPendingOrdersSnapshot final {
  std::vector<BitunixPendingOrder> orders;
  std::int64_t total = 0;
};

// Parses only the two authenticated, read-only reconciliation responses used by
// the Windows worker. Malformed JSON, non-zero Bitunix codes, missing required
// fields, type mismatches, duplicate required fields and oversized collections
// fail closed with std::nullopt.
[[nodiscard]] std::optional<std::vector<BitunixPendingPosition>>
ParseBitunixPendingPositionsResponse(std::string_view body) noexcept;

[[nodiscard]] std::optional<BitunixPendingOrdersSnapshot>
ParseBitunixPendingOrdersResponse(std::string_view body) noexcept;

}  // namespace quantara
