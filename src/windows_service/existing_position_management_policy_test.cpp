#include "existing_position_management_policy.h"

#include <iostream>

namespace {

using quantara::EvaluateExistingPortfolio;
using quantara::ExistingExchangePositionFacts;
using quantara::ExistingPositionClassification;
using quantara::ExistingPositionManagementAuthority;

ExistingExchangePositionFacts Verified(bool managed = false) {
  return {.position_id = "position-1",
          .symbol = "BTCUSDT",
          .isolated_margin = true,
          .has_unambiguous_quantara_identity = true,
          .has_complete_exchange_stop = true,
          .has_complete_exchange_take_profit_ladder = true,
          .has_conflicting_order_fill_or_history = false,
          .has_durable_reconstruction = true,
          .is_already_managed = managed};
}

bool Expect(bool condition, const char* message) {
  if (!condition) std::cerr << message << '\n';
  return condition;
}

}  // namespace

int main() {
  bool ok = true;
  const auto orphan = EvaluateExistingPortfolio({Verified()});
  ok &= Expect(orphan.classification ==
                   ExistingPositionClassification::kRecoverableOrphan &&
                   orphan.authority ==
                       ExistingPositionManagementAuthority::kManageExistingOnly &&
                   orphan.blocks_new_entries,
               "Verified orphan must be management-only and block entries.");

  auto unprotected = Verified();
  unprotected.has_complete_exchange_stop = false;
  const auto protection = EvaluateExistingPortfolio({unprotected});
  ok &= Expect(protection.authority ==
                   ExistingPositionManagementAuthority::kReconciliationOnly &&
                   protection.blocks_new_entries,
               "Missing stop must fail closed into reconciliation.");

  auto external = Verified();
  external.has_unambiguous_quantara_identity = false;
  const auto external_decision = EvaluateExistingPortfolio({external});
  ok &= Expect(external_decision.classification ==
                   ExistingPositionClassification::kExternalUnmanaged &&
                   external_decision.authority ==
                       ExistingPositionManagementAuthority::kNone &&
                   external_decision.blocks_new_entries,
               "External position must never be managed.");

  const auto portfolio = EvaluateExistingPortfolio({Verified(true), external});
  ok &= Expect(portfolio.authority == ExistingPositionManagementAuthority::kNone &&
                   portfolio.blocks_new_entries,
               "One external position must block the whole portfolio.");
  return ok ? 0 : 1;
}
