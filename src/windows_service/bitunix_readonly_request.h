#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "bitunix_request_authorizer.h"

namespace quantara {

enum class BitunixReadOnlyEndpoint {
  kPendingPositions,
  kPendingOrders,
};

struct BitunixReadOnlyRequest final {
  std::string host;
  std::string method;
  std::string path;
  std::vector<std::pair<std::string, std::string>> query;
  BitunixRequestAuthorization authorization;
};

// Builds an authenticated private Bitunix request description for the minimal
// exchange-truth reads needed by Windows reconciliation. The contract is
// deliberately allowlisted and GET-only. It performs no network I/O and grants
// no order, position-mutation, withdrawal, transfer, or entry authority.
std::optional<BitunixReadOnlyRequest> BuildBitunixReadOnlyRequest(
    const std::filesystem::path& credential_root, BitunixReadOnlyEndpoint endpoint,
    std::string_view nonce, std::string_view timestamp,
    const std::vector<std::pair<std::string, std::string>>& query = {}) noexcept;

}  // namespace quantara
