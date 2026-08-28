#include "bitunix_reconciliation_facts_adapter.h"

namespace quantara {

std::optional<ExistingExchangePositionFacts> BuildExistingExchangePositionFacts(
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
