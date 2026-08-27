#include "credential_readiness.h"

#include <windows.h>

#include <string>

#include "credential_vault.h"

namespace quantara {
namespace {

constexpr wchar_t kApiKeyName[] = L"bitunix-api-key";
constexpr wchar_t kApiSecretName[] = L"bitunix-api-secret";

void Wipe(std::string& value) noexcept {
  if (!value.empty()) {
    SecureZeroMemory(value.data(), value.size());
  }
  value.clear();
}

}  // namespace

CredentialReadiness EvaluateCredentialReadiness(
    const std::filesystem::path& root) noexcept {
  std::string api_key;
  std::string api_secret;
  try {
    CredentialVault vault(root);
    auto loaded_key = vault.Load(kApiKeyName);
    auto loaded_secret = vault.Load(kApiSecretName);

    const bool key_present = loaded_key.has_value();
    const bool secret_present = loaded_secret.has_value();
    if (loaded_key.has_value()) {
      api_key = std::move(*loaded_key);
    }
    if (loaded_secret.has_value()) {
      api_secret = std::move(*loaded_secret);
    }

    CredentialReadiness result = CredentialReadiness::kIncomplete;
    if (!key_present && !secret_present) {
      result = CredentialReadiness::kMissing;
    } else if (key_present && secret_present && !api_key.empty() &&
               !api_secret.empty()) {
      result = CredentialReadiness::kReady;
    } else if ((key_present && api_key.empty()) ||
               (secret_present && api_secret.empty())) {
      result = CredentialReadiness::kInvalid;
    }

    Wipe(api_key);
    Wipe(api_secret);
    return result;
  } catch (...) {
    Wipe(api_key);
    Wipe(api_secret);
    return CredentialReadiness::kInvalid;
  }
}

}  // namespace quantara
