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
[[nodiscard]] std::optional<ExistingExchangePositionFacts>
BuildExistingExchangePositionFacts(
    const BitunixPendingPosition& position,
    const DurableReconciliationEvidence& evidence) noexcept;

}  // namespace quantara
