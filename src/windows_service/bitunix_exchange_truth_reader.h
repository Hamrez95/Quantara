#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "bitunix_exchange_truth_parser.h"
#include "bitunix_https_readonly_transport.h"
#include "bitunix_pending_tpsl_parser.h"

namespace quantara {

struct BitunixReadOnlyAuthStamp final {
  std::string nonce;
  std::string timestamp;
};

struct BitunixExchangeTruthSnapshot final {
  std::vector<BitunixPendingPosition> positions;
  BitunixPendingOrdersSnapshot pending_orders;
  std::vector<BitunixPendingTpSlOrder> pending_tpsl_orders;
};

using BitunixReadOnlyTransport = std::optional<BitunixHttpsReadOnlyResponse> (*)(
    const BitunixReadOnlyHttpEnvelope& envelope,
    const BitunixHttpsReadOnlyLimits& limits) noexcept;

// Generates one fresh authentication stamp for a private read. The nonce uses
// the Windows system-preferred CSPRNG and the timestamp is current Unix epoch
// milliseconds. Failure to obtain either value is fail-closed.
[[nodiscard]] std::optional<BitunixReadOnlyAuthStamp>
GenerateBitunixReadOnlyAuthStamp() noexcept;

// Executes one bounded, authenticated, read-only reconciliation cycle against
// the three allowlisted Bitunix endpoints. The cycle is accepted only when all
// responses parse successfully, the generic pending-order page is complete,
// and the TP/SL response cannot be a saturated/truncated page. It never grants
// execution authority and performs no order/position mutation.
[[nodiscard]] std::optional<BitunixExchangeTruthSnapshot>
ReadBitunixExchangeTruth(
    const std::filesystem::path& credential_root,
    const BitunixReadOnlyAuthStamp& positions_auth,
    const BitunixReadOnlyAuthStamp& orders_auth,
    const BitunixReadOnlyAuthStamp& tpsl_auth,
    BitunixReadOnlyTransport transport = ExecuteBitunixHttpsReadOnly,
    const BitunixHttpsReadOnlyLimits& limits = {}) noexcept;

}  // namespace quantara
