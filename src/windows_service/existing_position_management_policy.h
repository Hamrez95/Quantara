#pragma once

#include <string_view>
#include <vector>

namespace quantara {

// Facts must be fetched from the exchange during the current reconciliation
// cycle. Cached/local state is deliberately not an input to this boundary.
struct ExistingExchangePositionFacts final {
  std::string_view position_id;
  std::string_view symbol;
  bool isolated_margin = false;
  bool has_unambiguous_quantara_identity = false;
  bool has_complete_exchange_stop = false;
  bool has_complete_exchange_take_profit_ladder = false;
  bool has_conflicting_order_fill_or_history = true;
  bool has_durable_reconstruction = false;
  bool is_already_managed = false;
};

enum class ExistingPositionClassification {
  kManaged,
  kRecoverableOrphan,
  kExternalUnmanaged,
  kAmbiguous,
};

enum class ExistingPositionManagementAuthority {
  kNone,
  kReconciliationOnly,
  kManageExistingOnly,
};

struct ExistingPositionManagementDecision final {
  ExistingPositionClassification classification;
  ExistingPositionManagementAuthority authority;
  bool blocks_new_entries;
  std::string_view reason;
};

ExistingPositionManagementDecision ClassifyExistingExchangePosition(
    const ExistingExchangePositionFacts& facts) noexcept;

// Any external or ambiguous position blocks management of the whole portfolio.
ExistingPositionManagementDecision EvaluateExistingPortfolio(
    const std::vector<ExistingExchangePositionFacts>& positions) noexcept;

}  // namespace quantara
