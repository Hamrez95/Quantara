#include "bitunix_request_signer.h"

#include <windows.h>
#include <bcrypt.h>

#include <algorithm>
#include <array>
#include <limits>

namespace quantara {
namespace {

std::optional<std::string> Sha256Hex(std::string_view value) noexcept {
  if (value.size() > static_cast<size_t>(std::numeric_limits<ULONG>::max())) {
    return std::nullopt;
  }

  std::array<unsigned char, 32> hash{};
  const auto status = BCryptHash(
      BCRYPT_SHA256_ALG_HANDLE, nullptr, 0,
      reinterpret_cast<PUCHAR>(const_cast<char*>(value.data())),
      static_cast<ULONG>(value.size()), hash.data(),
      static_cast<ULONG>(hash.size()));
  if (status < 0) return std::nullopt;

  static constexpr char kHex[] = "0123456789abcdef";
  std::string encoded(hash.size() * 2, '0');
  for (size_t index = 0; index < hash.size(); ++index) {
    encoded[index * 2] = kHex[(hash[index] >> 4) & 0x0f];
    encoded[index * 2 + 1] = kHex[hash[index] & 0x0f];
  }
  SecureZeroMemory(hash.data(), hash.size());
  return encoded;
}

}  // namespace

std::optional<BitunixRequestSignature> CreateBitunixRequestSignature(
    std::string_view nonce, std::string_view timestamp,
    std::string_view api_key, std::string_view secret_key,
    const std::vector<std::pair<std::string, std::string>>& query,
    std::string_view body) noexcept {
  try {
    auto sorted_query = query;
    std::sort(sorted_query.begin(), sorted_query.end(),
              [](const auto& left, const auto& right) {
                return left.first < right.first;
              });

    size_t query_size = 0;
    for (const auto& [key, value] : sorted_query) {
      query_size += key.size() + value.size();
    }

    std::string canonical;
    canonical.reserve(nonce.size() + timestamp.size() + api_key.size() +
                      query_size + body.size());
    canonical.append(nonce);
    canonical.append(timestamp);
    canonical.append(api_key);
    for (const auto& [key, value] : sorted_query) {
      canonical.append(key);
      canonical.append(value);
    }
    canonical.append(body);

    const auto digest = Sha256Hex(canonical);
    SecureZeroMemory(canonical.data(), canonical.size());
    if (!digest.has_value()) return std::nullopt;

    std::string signing_input = *digest;
    signing_input.append(secret_key);
    const auto sign = Sha256Hex(signing_input);
    SecureZeroMemory(signing_input.data(), signing_input.size());
    if (!sign.has_value()) return std::nullopt;

    return BitunixRequestSignature{*digest, *sign};
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
