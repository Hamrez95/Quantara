#include "bitunix_request_authorizer.h"

#include <windows.h>

#include <optional>
#include <string>

#include "bitunix_request_signer.h"
#include "credential_vault.h"

namespace quantara {
namespace {

constexpr wchar_t kApiKeyName[] = L"bitunix-api-key";
constexpr wchar_t kApiSecretName[] = L"bitunix-api-secret";

void Wipe(std::optional<std::string>& value) noexcept {
  if (!value.has_value()) return;
  if (!value->empty()) SecureZeroMemory(value->data(), value->size());
  value->clear();
  value.reset();
}

}  // namespace

std::optional<BitunixRequestAuthorization> AuthorizeBitunixPrivateRequest(
    const std::filesystem::path& credential_root, std::string_view nonce,
    std::string_view timestamp,
    const std::vector<std::pair<std::string, std::string>>& query,
    std::string_view body) noexcept {
  if (nonce.empty() || timestamp.empty()) return std::nullopt;

  std::optional<std::string> api_key;
  std::optional<std::string> api_secret;
  try {
    CredentialVault vault(credential_root);
    api_key = vault.Load(kApiKeyName);
    api_secret = vault.Load(kApiSecretName);
    if (!api_key.has_value() || !api_secret.has_value() || api_key->empty() ||
        api_secret->empty()) {
      Wipe(api_key);
      Wipe(api_secret);
      return std::nullopt;
    }

    const auto signature = CreateBitunixRequestSignature(
        nonce, timestamp, *api_key, *api_secret, query, body);
    Wipe(api_secret);
    if (!signature.has_value()) {
      Wipe(api_key);
      return std::nullopt;
    }

    BitunixRequestAuthorization result{*api_key,
                                       std::string(nonce),
                                       std::string(timestamp),
                                       signature->digest,
                                       signature->sign};
    Wipe(api_key);
    return result;
  } catch (...) {
    Wipe(api_key);
    Wipe(api_secret);
    return std::nullopt;
  }
}

}  // namespace quantara
