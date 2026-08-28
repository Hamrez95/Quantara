#include "bitunix_exchange_truth_reader.h"

#include <windows.h>
#include <bcrypt.h>

#include <array>
#include <chrono>
#include <cstdint>
#include <utility>
#include <vector>

#include "bitunix_readonly_request.h"

namespace quantara {
namespace {

std::optional<BitunixHttpsReadOnlyResponse> Execute(
    BitunixReadOnlyTransport transport,
    const std::optional<BitunixReadOnlyRequest>& request,
    const BitunixHttpsReadOnlyLimits& limits) noexcept {
  if (transport == nullptr || !request.has_value()) return std::nullopt;
  const auto envelope = BuildBitunixReadOnlyHttpEnvelope(*request);
  if (!envelope.has_value()) return std::nullopt;
  const auto response = transport(*envelope, limits);
  if (!response.has_value() || response->status_code != 200) return std::nullopt;
  return response;
}

bool ValidAuthStamp(const BitunixReadOnlyAuthStamp& stamp) noexcept {
  return !stamp.nonce.empty() && !stamp.timestamp.empty();
}

}  // namespace

std::optional<BitunixReadOnlyAuthStamp>
GenerateBitunixReadOnlyAuthStamp() noexcept {
  try {
    std::array<unsigned char, 16> random_bytes{};
    if (BCryptGenRandom(nullptr, random_bytes.data(),
                        static_cast<ULONG>(random_bytes.size()),
                        BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
      return std::nullopt;
    }

    constexpr char kHex[] = "0123456789abcdef";
    std::string nonce;
    nonce.reserve(random_bytes.size() * 2);
    for (const auto byte : random_bytes) {
      nonce.push_back(kHex[(byte >> 4) & 0x0f]);
      nonce.push_back(kHex[byte & 0x0f]);
    }

    const auto now = std::chrono::system_clock::now().time_since_epoch();
    const auto timestamp_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(now).count();
    if (timestamp_ms <= 0) return std::nullopt;

    return BitunixReadOnlyAuthStamp{std::move(nonce),
                                    std::to_string(timestamp_ms)};
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<BitunixExchangeTruthSnapshot> ReadBitunixExchangeTruth(
    const std::filesystem::path& credential_root,
    const BitunixReadOnlyAuthStamp& positions_auth,
    const BitunixReadOnlyAuthStamp& orders_auth,
    BitunixReadOnlyTransport transport,
    const BitunixHttpsReadOnlyLimits& limits) noexcept {
  try {
    // Separate nonces prevent accidental replay/reuse between the two signed
    // private reads in one reconciliation cycle.
    if (credential_root.empty() || !ValidAuthStamp(positions_auth) ||
        !ValidAuthStamp(orders_auth) ||
        positions_auth.nonce == orders_auth.nonce) {
      return std::nullopt;
    }

    const auto positions_request = BuildBitunixReadOnlyRequest(
        credential_root, BitunixReadOnlyEndpoint::kPendingPositions,
        positions_auth.nonce, positions_auth.timestamp);
    const auto positions_response = Execute(transport, positions_request, limits);
    if (!positions_response.has_value()) return std::nullopt;

    auto positions =
        ParseBitunixPendingPositionsResponse(positions_response->body);
    if (!positions.has_value()) return std::nullopt;

    // Request the largest bounded first page supported by the existing
    // allowlisted contract. If Bitunix reports more rows than returned, refuse
    // the cycle rather than silently treating partial protection truth as
    // complete. Pagination can be added later with per-page fresh auth stamps.
    const std::vector<std::pair<std::string, std::string>> order_query = {
        {"limit", "100"}, {"skip", "0"}};
    const auto orders_request = BuildBitunixReadOnlyRequest(
        credential_root, BitunixReadOnlyEndpoint::kPendingOrders,
        orders_auth.nonce, orders_auth.timestamp, order_query);
    const auto orders_response = Execute(transport, orders_request, limits);
    if (!orders_response.has_value()) return std::nullopt;

    auto orders = ParseBitunixPendingOrdersResponse(orders_response->body);
    if (!orders.has_value() || orders->total < 0 ||
        static_cast<std::uint64_t>(orders->total) != orders->orders.size()) {
      return std::nullopt;
    }

    return BitunixExchangeTruthSnapshot{std::move(*positions),
                                        std::move(*orders)};
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
