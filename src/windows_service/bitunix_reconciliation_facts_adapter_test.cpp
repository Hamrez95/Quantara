#include "bitunix_reconciliation_facts_adapter.h"

#include <iostream>

namespace {

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

quantara::BitunixPendingPosition Position(
    const char* position_id = "pos-1",
    const char* symbol = "BTCUSDT",
    const char* margin_mode = "ISOLATION") {
  quantara::BitunixPendingPosition position{};
  position.position_id = position_id;
  position.symbol = symbol;
  position.side = "LONG";
  position.margin_mode = margin_mode;
  position.position_mode = "ONE_WAY";
  position.quantity = "0.001";
  position.leverage = 5;
  return position;
}

quantara::DurableReconciliationEvidence VerifiedEvidence() {
  quantara::DurableReconciliationEvidence evidence{};
  evidence.position_id = "pos-1";
  evidence.symbol = "BTCUSDT";
  evidence.has_unambiguous_quantara_identity = true;
  evidence.has_complete_exchange_stop = true;
  evidence.has_complete_exchange_take_profit_ladder = true;
  evidence.has_conflicting_order_fill_or_history = false;
  evidence.has_durable_reconstruction = true;
  evidence.is_already_managed = false;
  return evidence;
}

}  // namespace

int main() {
  bool ok = true;

  const auto position = Position();
  const auto verified = VerifiedEvidence();
  const auto facts =
      quantara::BuildExistingExchangePositionFacts(position, verified);
  ok &= Expect(facts.has_value(),
               "Matching exchange and durable identity must build facts.");
  if (facts.has_value()) {
    ok &= Expect(facts->position_id == "pos-1" &&
                     facts->symbol == "BTCUSDT" && facts->isolated_margin,
                 "Exchange identity and isolated margin must be preserved.");
    ok &= Expect(facts->has_unambiguous_quantara_identity &&
                     facts->has_complete_exchange_stop &&
                     facts->has_complete_exchange_take_profit_ladder &&
                     !facts->has_conflicting_order_fill_or_history &&
                     facts->has_durable_reconstruction &&
                     !facts->is_already_managed,
                 "Explicit reconciliation evidence must map without inference.");

    const auto decision = quantara::ClassifyExistingExchangePosition(*facts);
    ok &= Expect(
        decision.classification ==
                quantara::ExistingPositionClassification::kRecoverableOrphan &&
            decision.authority ==
                quantara::ExistingPositionManagementAuthority::kManageExistingOnly,
        "Fully verified evidence may grant existing-position management only.");
  }

  auto mismatched_position = VerifiedEvidence();
  mismatched_position.position_id = "pos-other";
  ok &= Expect(!quantara::BuildExistingExchangePositionFacts(
                    position, mismatched_position)
                    .has_value(),
               "Position-id mismatch must fail closed.");

  auto mismatched_symbol = VerifiedEvidence();
  mismatched_symbol.symbol = "ETHUSDT";
  ok &= Expect(!quantara::BuildExistingExchangePositionFacts(position,
                                                               mismatched_symbol)
                    .has_value(),
               "Symbol mismatch must fail closed.");

  quantara::DurableReconciliationEvidence unknown{};
  unknown.position_id = "pos-1";
  unknown.symbol = "BTCUSDT";
  const auto unknown_facts =
      quantara::BuildExistingExchangePositionFacts(position, unknown);
  ok &= Expect(unknown_facts.has_value(),
               "Matching identity with missing evidence must remain classifiable.");
  if (unknown_facts.has_value()) {
    const auto decision =
        quantara::ClassifyExistingExchangePosition(*unknown_facts);
    ok &= Expect(
        decision.classification ==
                quantara::ExistingPositionClassification::kExternalUnmanaged &&
            decision.authority ==
                quantara::ExistingPositionManagementAuthority::kNone,
        "Missing ownership evidence must never be inferred from exchange truth.");
  }

  auto cross_position = Position("pos-1", "BTCUSDT", "CROSS");
  const auto cross_facts =
      quantara::BuildExistingExchangePositionFacts(cross_position, verified);
  ok &= Expect(cross_facts.has_value() && !cross_facts->isolated_margin,
               "Cross margin must be preserved as unsafe exchange truth.");
  if (cross_facts.has_value()) {
    const auto decision = quantara::ClassifyExistingExchangePosition(*cross_facts);
    ok &= Expect(
        decision.classification ==
                quantara::ExistingPositionClassification::kExternalUnmanaged &&
            decision.authority ==
                quantara::ExistingPositionManagementAuthority::kNone,
        "Cross margin must remain unmanaged even with otherwise verified evidence.");
  }

  auto protection_only = VerifiedEvidence();
  protection_only.has_unambiguous_quantara_identity = false;
  const auto protection_only_facts =
      quantara::BuildExistingExchangePositionFacts(position, protection_only);
  ok &= Expect(protection_only_facts.has_value(),
               "Protection evidence alone should still produce fail-closed facts.");
  if (protection_only_facts.has_value()) {
    const auto decision =
        quantara::ClassifyExistingExchangePosition(*protection_only_facts);
    ok &= Expect(
        decision.authority ==
            quantara::ExistingPositionManagementAuthority::kNone,
        "Protection metadata must not imply Quantara ownership.");
  }

  if (!ok) return 1;
  std::cout << "Bitunix reconciliation-facts adapter tests passed.\n";
  return 0;
}
