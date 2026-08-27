#include "credential_readiness.h"

#include <windows.h>

#include <optional>
#include <string>

#include "credential_vault.h"

namespace quantara {
namespace {

constexpr wchar_t kApiKeyName[] = L"bitunix-api-key";
constexpr wchar_t kApiSecretName[] = L"bitunix-api-secret";

void Wipe(std::optional<std::string>& value) noexcept {
  if (!value.has_value()) {
    return;
  }
  if (!value->empty()) {
    SecureZeroMemory(value->data(), value->size());
  }
  value->clear();
  value.reset();
}

}  // namespace

CredentialReadiness EvaluateCredentialReadiness(
    const std::filesystem::path& root) noexcept {
  std::optional<std::string> api_key;
  std::optional<std::string> api_secret;
  try {
    CredentialVault vault(root);
    api_key = vault.Load(kApiKeyName);
    api_secret = vault.Load(kApiSecretName);

    const bool key_present = api_key.has_value();
    const bool secret_present = api_secret.has_value();
    CredentialReadiness result = CredentialReadiness::kIncomplete;
    if (!key_present && !secret_present) {
      result = CredentialReadiness::kMissing;
    } else if (key_present && secret_present && !api_key->empty() &&
               !api_secret->empty()) {
      result = CredentialReadiness::kReady;
    } else if ((key_present && api_key->empty()) ||
               (secret_present && api_secret->empty())) {
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

bool CredentialReadinessRequiresReconciliation(
    CredentialReadiness readiness) noexcept {
  return readiness == CredentialReadiness::kIncomplete ||
         readiness == CredentialReadiness::kInvalid;
}

}  // namespace quantara
