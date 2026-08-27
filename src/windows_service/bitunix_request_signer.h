#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace quantara {

struct BitunixRequestSignature final {
  std::string digest;
  std::string sign;
};

// Mirrors the canonical Flutter BitunixRequestSigner contract exactly:
// SHA256(nonce + timestamp + apiKey + sorted(key + value) + body), followed by
// SHA256(digest + secretKey). This helper performs no network or order action.
std::optional<BitunixRequestSignature> CreateBitunixRequestSignature(
    std::string_view nonce, std::string_view timestamp,
    std::string_view api_key, std::string_view secret_key,
    const std::vector<std::pair<std::string, std::string>>& query = {},
    std::string_view body = {}) noexcept;

}  // namespace quantara
