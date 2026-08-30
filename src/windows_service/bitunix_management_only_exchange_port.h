#pragma once

#include "bitunix_exchange_truth_reader.h"
#include "bitunix_management_only_https_transport.h"
#include "../native/execution/management_only_mutation_executor.h"

#include <filesystem>
#include <optional>

namespace quantara {

using BitunixManagementOnlyTransport =
    std::optional<BitunixManagementOnlyHttpsResponse> (*)(
        const BitunixManagementOnlyHttpEnvelope& envelope,
        const BitunixManagementOnlyHttpsLimits& limits) noexcept;

// Windows-owned bridge from the shared management-only mutation executor to the
// one allowlisted Bitunix mutation transport. Submission never retries. Every
// confirmation performs a fresh authoritative positions + pending-orders read.
// The port can confirm only a reduce-only full close of the exact verified
// position; it exposes no new-entry, leverage, margin-mode, transfer or generic
// order mutation surface.
class BitunixManagementOnlyExchangePort final
    : public ExistingPositionMutationExchangePort {
 public:
  explicit BitunixManagementOnlyExchangePort(
      std::filesystem::path credential_root,
      BitunixManagementOnlyTransport mutation_transport =
          ExecuteBitunixManagementOnlyHttps,
      BitunixReadOnlyTransport read_only_transport = ExecuteBitunixHttpsReadOnly,
      BitunixManagementOnlyHttpsLimits mutation_limits = {},
      BitunixHttpsReadOnlyLimits read_only_limits = {}) noexcept;

  [[nodiscard]] ExistingPositionMutationSubmitOutcome SubmitMutation(
      const ExistingPositionMutationRequest& request) noexcept override;

  [[nodiscard]] ExistingPositionMutationConfirmation ConfirmMutation(
      const ExistingPositionMutationRequest& request) noexcept override;

 private:
  std::filesystem::path credential_root_;
  BitunixManagementOnlyTransport mutation_transport_ = nullptr;
  BitunixReadOnlyTransport read_only_transport_ = nullptr;
  BitunixManagementOnlyHttpsLimits mutation_limits_{};
  BitunixHttpsReadOnlyLimits read_only_limits_{};
};

}  // namespace quantara
