#pragma once

#include "existing_position_management_policy.h"

#include <string_view>

namespace quantara {

enum class ExistingPositionMutationSubmitOutcome {
  kAcknowledged,
  kOutcomeAmbiguous,
  kDefinitelyNotSubmitted,
};

enum class ExistingPositionMutationConfirmation {
  kConfirmedByFreshExchangeTruth,
  kNotConfirmedByFreshExchangeTruth,
  kExchangeTruthUnavailable,
};

struct ExistingPositionMutationExecutionResult final {
  bool completed = false;
  bool submission_attempted = false;
  bool exchange_truth_reconciled = false;
  std::string_view reason;
};

// Narrow platform adapter for an already-authorized existing-position mutation.
// Implementations must never expose new-entry, leverage, transfer, or margin-mode
// mutation methods through this boundary. ConfirmMutation must perform a fresh
// authoritative exchange read; an HTTP acknowledgement alone is not confirmation.
class ExistingPositionMutationExchangePort {
 public:
  virtual ~ExistingPositionMutationExchangePort() = default;

  [[nodiscard]] virtual ExistingPositionMutationSubmitOutcome SubmitMutation(
      const ExistingPositionMutationRequest& request) noexcept = 0;

  [[nodiscard]] virtual ExistingPositionMutationConfirmation ConfirmMutation(
      const ExistingPositionMutationRequest& request) noexcept = 0;
};

// Executes one bounded management-only mutation. The shared policy is checked
// immediately before submission. Every submission attempt is followed by fresh
// exchange confirmation, including timeout/ambiguous outcomes. This class never
// retries a mutation: callers must start a new reconciliation cycle before any
// later attempt.
[[nodiscard]] ExistingPositionMutationExecutionResult
ExecuteExistingPositionMutation(
    const ExistingPositionManagementDecision& portfolio_decision,
    const ExistingExchangePositionFacts& position,
    const ExistingPositionMutationRequest& request,
    ExistingPositionMutationExchangePort& exchange) noexcept;

}  // namespace quantara
