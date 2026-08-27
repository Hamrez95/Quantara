#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace quantara {

struct BitunixRequestAuthorization final {
  std::string api_key;
  std::string nonce;
  std::string timestamp;
  std::string digest;
  std::string sign;
};

// Loads the existing DPAPI-protected Bitunix credential pair and creates the
// canonical private-request authorization fields. This helper performs no HTTP
// request and grants no order/execution authority.
std::optional<BitunixRequestAuthorization> AuthorizeBitunixPrivateRequest(
    const std::filesystem::path& credential_root, std::string_view nonce,
    std::string_view timestamp,
    const std::vector<std::pair<std::string, std::string>>& query = {},
    std::string_view body = {}) noexcept;

}  // namespace quantara
