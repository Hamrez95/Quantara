#pragma once

#include <string_view>
#include <vector>

namespace quantara {

enum class ExistingPositionSide {
  kUnknown,
  kLong,
  kShort,
};

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
  // Exchange-derived stop evidence is deliberately carried separately from the
  // local mutation request. A stop-tightening decision must never infer either
  // the current stop or the position side from caller intent.
  ExistingPositionSide side = ExistingPositionSide::kUnknown;
  double current_stop_price = 0.0;
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

enum class ExistingPositionMutationKind {
  kReduceOnlyClose,
  kTightenStop,
  kUnsupported,
};

// Mutation facts are intentionally narrow. This contract cannot express a new
// entry, leverage increase, margin-mode expansion, or stop widening as an
// allowed action. Platform adapters must still bind these facts to the exact
// current exchange position before submitting any request.
struct ExistingPositionMutationRequest final {
  ExistingPositionMutationKind kind = ExistingPositionMutationKind::kUnsupported;
  std::string_view position_id;
  std::string_view symbol;
  bool reduce_only = false;
  bool increases_exposure = true;
  bool changes_margin_mode = true;
  bool widens_stop = true;
  // Explicit requested stop. It is meaningful only for kTightenStop and must be
  // proven safer than exchange-derived current_stop_price for the verified side.
  double new_stop_price = 0.0;
};

struct ExistingPositionMutationDecision final {
  bool allowed = false;
  std::string_view reason;
};

ExistingPositionManagementDecision ClassifyExistingExchangePosition(
    const ExistingExchangePositionFacts& facts) noexcept;

// Any external or ambiguous position blocks management of the whole portfolio.
ExistingPositionManagementDecision EvaluateExistingPortfolio(
    const std::vector<ExistingExchangePositionFacts>& positions) noexcept;

// Authorizes only bounded management of a freshly verified Quantara-owned
// existing position. It never grants entry authority. A Windows/Bitunix adapter
// must pass through this gate immediately before a mutation and reconcile fresh
// exchange truth again afterward.
ExistingPositionMutationDecision AuthorizeExistingPositionMutation(
    const ExistingPositionManagementDecision& portfolio_decision,
    const ExistingExchangePositionFacts& position,
    const ExistingPositionMutationRequest& request) noexcept;

}  // namespace quantara
