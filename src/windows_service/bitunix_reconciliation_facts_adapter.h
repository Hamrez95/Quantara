#pragma once

#include "bitunix_exchange_truth_parser.h"
#include "bitunix_pending_tpsl_parser.h"
#include "../native/execution/existing_position_management_policy.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cctype>
#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace quantara {

// Evidence that cannot be inferred safely from a pending-position response.
// Callers must populate protection facts only from the current exchange
// reconciliation cycle and ownership/reconstruction flags only from durable
// Quantara state. Defaults deliberately fail closed.
struct DurableReconciliationEvidence final {
  std::string position_id;
  std::string symbol;
  bool has_unambiguous_quantara_identity = false;
  bool has_complete_exchange_stop = false;
  bool has_complete_exchange_take_profit_ladder = false;
  bool has_conflicting_order_fill_or_history = true;
  bool has_durable_reconstruction = false;
  bool is_already_managed = false;
  // Current-cycle exchange stop facts. ApplyCurrentExchangeProtectionEvidence
  // replaces these on every reconciliation; durable callers must not supply or
  // rely on cached values for mutation authorization.
  double current_stop_price = 0.0;
  std::string current_stop_trigger_type;
  // Durable Quantara state must provide how many live reduce-only TP orders are
  // expected for this reconstructed position. Zero means unknown and can never
  // satisfy the complete-ladder gate.
  std::size_t expected_take_profit_order_count = 0;
};

namespace bitunix_reconciliation_quantity_detail {

struct DecimalAmount final {
  std::string digits;
  std::size_t scale = 0;
};

// Parses a strictly positive, plain decimal quantity without floating-point
// rounding. Scientific notation, signs, empty fractions and oversized values
// fail closed. Exchange quantity strings are bounded by the JSON parser.
[[nodiscard]] inline std::optional<DecimalAmount> ParsePositiveDecimal(
    std::string_view value) noexcept {
  if (value.empty() || value.size() > 512) return std::nullopt;

  std::string digits;
  try {
    digits.reserve(value.size());
    bool decimal_seen = false;
    std::size_t scale = 0;
    std::size_t integer_digits = 0;
    std::size_t fractional_digits = 0;
    for (const unsigned char c : value) {
      if (c == '.') {
        if (decimal_seen || integer_digits == 0) return std::nullopt;
        decimal_seen = true;
        continue;
      }
      if (std::isdigit(c) == 0) return std::nullopt;
      digits.push_back(static_cast<char>(c));
      if (decimal_seen) {
        ++fractional_digits;
        ++scale;
      } else {
        ++integer_digits;
      }
    }
    if (integer_digits == 0 || (decimal_seen && fractional_digits == 0)) {
      return std::nullopt;
    }

    const auto first_non_zero = digits.find_first_not_of('0');
    if (first_non_zero == std::string::npos) return std::nullopt;
    digits.erase(0, first_non_zero);
    return DecimalAmount{std::move(digits), scale};
  } catch (...) {
    return std::nullopt;
  }
}

[[nodiscard]] inline std::optional<double> ParsePositiveFinitePrice(
    std::string_view value) noexcept {
  if (value.empty() || value.size() > 512) return std::nullopt;
  double parsed = 0.0;
  const auto result =
      std::from_chars(value.data(), value.data() + value.size(), parsed);
  if (result.ec != std::errc{} || result.ptr != value.data() + value.size() ||
      !std::isfinite(parsed) || parsed <= 0.0) {
    return std::nullopt;
  }
  return parsed;
}

[[nodiscard]] inline bool IsSupportedStopTriggerType(
    std::string_view value) noexcept {
  return value == "LAST_PRICE" || value == "MARK_PRICE";
}

[[nodiscard]] inline std::string ScaledInteger(const DecimalAmount& amount,
                                               std::size_t scale) {
  std::string result = amount.digits;
  if (scale > amount.scale) result.append(scale - amount.scale, '0');
  return result;
}

inline void TrimLeadingZeros(std::string& value) noexcept {
  const auto first_non_zero = value.find_first_not_of('0');
  if (first_non_zero == std::string::npos) {
    value = "0";
  } else if (first_non_zero > 0) {
    value.erase(0, first_non_zero);
  }
}

[[nodiscard]] inline std::string AddUnsignedIntegers(std::string_view lhs,
                                                     std::string_view rhs) {
  std::string result;
  result.reserve(std::max(lhs.size(), rhs.size()) + 1);
  std::size_t left = lhs.size();
  std::size_t right = rhs.size();
  int carry = 0;
  while (left > 0 || right > 0 || carry != 0) {
    int sum = carry;
    if (left > 0) sum += lhs[--left] - '0';
    if (right > 0) sum += rhs[--right] - '0';
    result.push_back(static_cast<char>('0' + (sum % 10)));
    carry = sum / 10;
  }
  std::reverse(result.begin(), result.end());
  return result;
}

[[nodiscard]] inline bool DecimalEquals(std::string_view lhs,
                                        std::string_view rhs) noexcept {
  try {
    const auto left = ParsePositiveDecimal(lhs);
    const auto right = ParsePositiveDecimal(rhs);
    if (!left.has_value() || !right.has_value()) return false;
    const auto scale = std::max(left->scale, right->scale);
    auto left_scaled = ScaledInteger(*left, scale);
    auto right_scaled = ScaledInteger(*right, scale);
    TrimLeadingZeros(left_scaled);
    TrimLeadingZeros(right_scaled);
    return left_scaled == right_scaled;
  } catch (...) {
    return false;
  }
}

[[nodiscard]] inline bool DecimalSumEquals(
    const std::vector<std::string_view>& quantities,
    std::string_view target) noexcept {
  try {
    const auto parsed_target = ParsePositiveDecimal(target);
    if (!parsed_target.has_value() || quantities.empty()) return false;

    std::vector<DecimalAmount> parsed;
    parsed.reserve(quantities.size());
    std::size_t common_scale = parsed_target->scale;
    for (const auto quantity : quantities) {
      const auto amount = ParsePositiveDecimal(quantity);
      if (!amount.has_value()) return false;
      common_scale = std::max(common_scale, amount->scale);
      parsed.push_back(*amount);
    }

    std::string total = "0";
    for (const auto& amount : parsed) {
      total = AddUnsignedIntegers(total, ScaledInteger(amount, common_scale));
    }
    auto expected = ScaledInteger(*parsed_target, common_scale);
    TrimLeadingZeros(total);
    TrimLeadingZeros(expected);
    return total == expected;
  } catch (...) {
    return false;
  }
}

}  // namespace bitunix_reconciliation_quantity_detail

// Replaces only the current-cycle protection facts using complete generic
// pending-order truth plus the dedicated TP/SL quantity snapshot. Durable
// ownership/reconstruction facts are preserved exactly.
//
// Management authority requires one exchange-native stop whose quantity equals
// the entire current position and an explicit expected TP count whose quantities
// sum exactly to that same position quantity. Every TP must also carry a positive
// finite trigger price and an explicitly supported trigger semantic. Quantity
// math uses decimal strings, never binary floating point. Ambiguous identity,
// duplicate TP/SL ids, malformed quantities/prices, incomplete rows, unsupported
// trigger semantics, or non-reduce-only generic orders fail closed.
[[nodiscard]] inline std::optional<DurableReconciliationEvidence>
ApplyCurrentExchangeProtectionEvidence(
    const BitunixPendingPosition& position,
    const DurableReconciliationEvidence& durable,
    const BitunixPendingOrdersSnapshot& pending_orders,
    const std::vector<BitunixPendingTpSlOrder>& pending_tpsl_orders) noexcept {
  if (position.position_id.empty() || position.symbol.empty() ||
      !bitunix_reconciliation_quantity_detail::ParsePositiveDecimal(
           position.quantity)
           .has_value() ||
      durable.position_id != position.position_id ||
      durable.symbol != position.symbol || pending_orders.total < 0 ||
      static_cast<std::size_t>(pending_orders.total) !=
          pending_orders.orders.size()) {
    return std::nullopt;
  }

  auto joined = durable;
  joined.has_complete_exchange_stop = false;
  joined.has_complete_exchange_take_profit_ladder = false;
  joined.current_stop_price = 0.0;
  joined.current_stop_trigger_type.clear();

  // Generic pending orders remain useful as conflict evidence. Protection
  // completeness itself is sourced from the dedicated TP/SL endpoint because
  // that is where Bitunix exposes the actual protective quantities.
  for (const auto& order : pending_orders.orders) {
    const bool same_position_id =
        !order.position_id.empty() && order.position_id == position.position_id;
    const bool same_symbol = order.symbol == position.symbol;
    if (same_position_id != same_symbol) {
      joined.has_conflicting_order_fill_or_history = true;
      continue;
    }
    if (same_position_id && (!order.reduce_only || order.status != "NEW")) {
      joined.has_conflicting_order_fill_or_history = true;
    }
  }

  std::size_t stop_count = 0;
  std::size_t take_profit_count = 0;
  bool stop_candidate_valid = false;
  double stop_candidate_price = 0.0;
  std::string stop_candidate_trigger_type;
  std::vector<std::string_view> take_profit_quantities;
  take_profit_quantities.reserve(pending_tpsl_orders.size());

  for (std::size_t i = 0; i < pending_tpsl_orders.size(); ++i) {
    const auto& order = pending_tpsl_orders[i];
    const bool same_position_id =
        !order.position_id.empty() && order.position_id == position.position_id;
    const bool same_symbol = order.symbol == position.symbol;
    if (same_position_id != same_symbol) {
      joined.has_conflicting_order_fill_or_history = true;
      continue;
    }
    if (!same_position_id) continue;

    if (order.order_id.empty()) {
      joined.has_conflicting_order_fill_or_history = true;
      continue;
    }
    for (std::size_t previous = 0; previous < i; ++previous) {
      const auto& prior = pending_tpsl_orders[previous];
      if (prior.position_id == position.position_id &&
          prior.symbol == position.symbol && prior.order_id == order.order_id) {
        joined.has_conflicting_order_fill_or_history = true;
        break;
      }
    }

    const bool has_stop_price = !order.stop_loss_price.empty();
    const bool has_stop_quantity = !order.stop_loss_quantity.empty();
    if (has_stop_price != has_stop_quantity) {
      joined.has_conflicting_order_fill_or_history = true;
    } else if (has_stop_price) {
      ++stop_count;
      const auto parsed_price =
          bitunix_reconciliation_quantity_detail::ParsePositiveFinitePrice(
              order.stop_loss_price);
      const bool full_quantity =
          bitunix_reconciliation_quantity_detail::DecimalEquals(
              order.stop_loss_quantity, position.quantity);
      const bool valid_trigger =
          bitunix_reconciliation_quantity_detail::IsSupportedStopTriggerType(
              order.stop_loss_stop_type);
      if (!parsed_price.has_value() || !full_quantity || !valid_trigger) {
        joined.has_conflicting_order_fill_or_history = true;
      } else {
        stop_candidate_valid = true;
        stop_candidate_price = *parsed_price;
        stop_candidate_trigger_type = order.stop_loss_stop_type;
      }
    }

    const bool has_tp_price = !order.take_profit_price.empty();
    const bool has_tp_quantity = !order.take_profit_quantity.empty();
    if (has_tp_price != has_tp_quantity) {
      joined.has_conflicting_order_fill_or_history = true;
    } else if (has_tp_price) {
      ++take_profit_count;
      const bool valid_price =
          bitunix_reconciliation_quantity_detail::ParsePositiveFinitePrice(
              order.take_profit_price)
              .has_value();
      const bool valid_quantity =
          bitunix_reconciliation_quantity_detail::ParsePositiveDecimal(
              order.take_profit_quantity)
              .has_value();
      const bool valid_trigger =
          bitunix_reconciliation_quantity_detail::IsSupportedStopTriggerType(
              order.take_profit_stop_type);
      if (!valid_price || !valid_quantity || !valid_trigger) {
        joined.has_conflicting_order_fill_or_history = true;
      } else {
        take_profit_quantities.push_back(order.take_profit_quantity);
      }
    }
  }

  joined.has_complete_exchange_stop = stop_count == 1 && stop_candidate_valid;
  if (joined.has_complete_exchange_stop) {
    joined.current_stop_price = stop_candidate_price;
    joined.current_stop_trigger_type = std::move(stop_candidate_trigger_type);
  }

  joined.has_complete_exchange_take_profit_ladder =
      joined.expected_take_profit_order_count > 0 &&
      take_profit_count == joined.expected_take_profit_order_count &&
      take_profit_quantities.size() == take_profit_count &&
      bitunix_reconciliation_quantity_detail::DecimalSumEquals(
          take_profit_quantities, position.quantity);

  return joined;
}

// Joins parsed Bitunix position truth with explicit durable/current-cycle
// evidence. Identity mismatches or missing exchange identity fail closed.
// The returned identity string_views borrow from `position`, so the caller must
// keep the parsed position alive while consuming the facts. Current stop trigger
// evidence is copied and owned by the facts object.
[[nodiscard]] inline std::optional<ExistingExchangePositionFacts>
BuildExistingExchangePositionFacts(
    const BitunixPendingPosition& position,
    const DurableReconciliationEvidence& evidence) noexcept {
  if (position.position_id.empty() || position.symbol.empty()) {
    return std::nullopt;
  }
  if (evidence.position_id != position.position_id ||
      evidence.symbol != position.symbol) {
    return std::nullopt;
  }

  ExistingExchangePositionFacts facts{};
  facts.position_id = position.position_id;
  facts.symbol = position.symbol;
  facts.isolated_margin = position.margin_mode == "ISOLATION";
  facts.has_unambiguous_quantara_identity =
      evidence.has_unambiguous_quantara_identity;
  facts.has_complete_exchange_stop = evidence.has_complete_exchange_stop;
  facts.has_complete_exchange_take_profit_ladder =
      evidence.has_complete_exchange_take_profit_ladder;
  facts.has_conflicting_order_fill_or_history =
      evidence.has_conflicting_order_fill_or_history;
  facts.has_durable_reconstruction = evidence.has_durable_reconstruction;
  facts.is_already_managed = evidence.is_already_managed;
  if (position.side == "LONG") {
    facts.side = ExistingPositionSide::kLong;
  } else if (position.side == "SHORT") {
    facts.side = ExistingPositionSide::kShort;
  }
  if (evidence.has_complete_exchange_stop) {
    facts.current_stop_price = evidence.current_stop_price;
    facts.current_stop_trigger_type = evidence.current_stop_trigger_type;
  }
  return facts;
}

}  // namespace quantara
