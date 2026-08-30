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

// Testable three-stamp form. Each private read must use its own nonce.
[[nodiscard]] std::optional<BitunixExchangeTruthSnapshot>
ReadBitunixExchangeTruth(
    const std::filesystem::path& credential_root,
    const BitunixReadOnlyAuthStamp& positions_auth,
    const BitunixReadOnlyAuthStamp& orders_auth,
    const BitunixReadOnlyAuthStamp& tpsl_auth,
    BitunixReadOnlyTransport transport,
    const BitunixHttpsReadOnlyLimits& limits = {}) noexcept;

// Runtime convenience form preserves the existing service call contract while
// generating a fresh independent auth stamp for the third TP/SL truth read.
// The cycle is accepted only when all three allowlisted GET responses parse
// successfully, the generic pending-order page is complete, and the TP/SL page
// is not saturated at its maximum bounded page size. No mutation authority is
// granted by this reader.
[[nodiscard]] std::optional<BitunixExchangeTruthSnapshot>
ReadBitunixExchangeTruth(
    const std::filesystem::path& credential_root,
    const BitunixReadOnlyAuthStamp& positions_auth,
    const BitunixReadOnlyAuthStamp& orders_auth,
    BitunixReadOnlyTransport transport = ExecuteBitunixHttpsReadOnly,
    const BitunixHttpsReadOnlyLimits& limits = {}) noexcept;

}  // namespace quantara
