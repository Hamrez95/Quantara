#pragma once

#include "bitunix_exchange_truth_parser.h"
#include "../native/execution/existing_position_management_policy.h"

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
};

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
