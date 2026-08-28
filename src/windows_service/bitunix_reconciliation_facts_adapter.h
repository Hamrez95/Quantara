#pragma once

#include "bitunix_exchange_truth_parser.h"
#include "../native/execution/existing_position_management_policy.h"

#include <cstddef>
#include <optional>
#include <string>

namespace quantara {

// Evidence that cannot be inferred safely from a pending-position response.
// Callers must populate protection flags only from the current exchange
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
  // Durable Quantara state must provide how many live reduce-only TP orders are
  // expected for this reconstructed position. Zero means unknown and can never
  // satisfy the complete-ladder gate.
  std::size_t expected_take_profit_order_count = 0;
};

// Replaces only the current-cycle protection flags using the complete pending
// order snapshot. Durable ownership/reconstruction facts are preserved exactly.
// A matching non-reduce-only/non-NEW order or contradictory position/symbol
// identity is treated as a conflict. TP completeness is never inferred unless
// durable state supplied an explicit expected order count. The scan is bounded
// by the exchange reader's 100-order page and performs no allocation.
[[nodiscard]] inline std::optional<DurableReconciliationEvidence>
ApplyCurrentExchangeProtectionEvidence(
    const BitunixPendingPosition& position,
    const DurableReconciliationEvidence& durable,
    const BitunixPendingOrdersSnapshot& pending_orders) noexcept {
  if (position.position_id.empty() || position.symbol.empty() ||
      durable.position_id != position.position_id ||
      durable.symbol != position.symbol || pending_orders.total < 0 ||
      static_cast<std::size_t>(pending_orders.total) !=
          pending_orders.orders.size()) {
    return std::nullopt;
  }

  auto joined = durable;
  joined.has_complete_exchange_stop = false;
  joined.has_complete_exchange_take_profit_ladder = false;

  std::size_t take_profit_order_count = 0;
  bool stop_seen = false;
  for (std::size_t i = 0; i < pending_orders.orders.size(); ++i) {
    const auto& order = pending_orders.orders[i];
    const bool same_position_id =
        !order.position_id.empty() && order.position_id == position.position_id;
    const bool same_symbol = order.symbol == position.symbol;

    if (same_position_id != same_symbol) {
      // A pending order that aliases only one half of the exchange identity is
      // ambiguous for this position and cannot contribute protection authority.
      joined.has_conflicting_order_fill_or_history = true;
      continue;
    }
    if (!same_position_id) continue;

    if (!order.reduce_only || order.status != "NEW") {
      joined.has_conflicting_order_fill_or_history = true;
      continue;
    }

    if (!order.stop_loss_price.empty()) stop_seen = true;
    if (!order.take_profit_price.empty()) {
      if (order.order_id.empty()) {
        joined.has_conflicting_order_fill_or_history = true;
        continue;
      }
      bool duplicate_order_id = false;
      for (std::size_t previous = 0; previous < i; ++previous) {
        const auto& prior = pending_orders.orders[previous];
        if (!prior.take_profit_price.empty() && prior.order_id == order.order_id) {
          duplicate_order_id = true;
          break;
        }
      }
      if (duplicate_order_id) {
        joined.has_conflicting_order_fill_or_history = true;
        continue;
      }
      ++take_profit_order_count;
    }
  }

  joined.has_complete_exchange_stop = stop_seen;
  joined.has_complete_exchange_take_profit_ladder =
      joined.expected_take_profit_order_count > 0 &&
      take_profit_order_count == joined.expected_take_profit_order_count;
  return joined;
}

// Joins parsed Bitunix position truth with explicit durable/current-cycle
// evidence. Identity mismatches or missing exchange identity fail closed.
// The returned string_views borrow from `position`, so the caller must keep the
// parsed position alive while consuming the facts.
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
  return facts;
}

}  // namespace quantara
