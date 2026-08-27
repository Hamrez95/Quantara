#include "credential_readiness.h"

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <string>

#include "credential_vault.h"

int wmain() {
  std::error_code cleanup_error;
  const auto root = std::filesystem::temp_directory_path() /
                    (L"quantara-credential-readiness-test-" +
                     std::to_wstring(GetCurrentProcessId()));
  std::filesystem::remove_all(root, cleanup_error);

  try {
    const auto missing = quantara::EvaluateCredentialReadiness(root);
    if (missing != quantara::CredentialReadiness::kMissing ||
        quantara::CredentialReadinessRequiresReconciliation(missing)) {
      return 1;
    }

    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-api-key", "test-key");
    const auto incomplete = quantara::EvaluateCredentialReadiness(root);
    if (incomplete != quantara::CredentialReadiness::kIncomplete ||
        !quantara::CredentialReadinessRequiresReconciliation(incomplete)) {
      std::filesystem::remove_all(root, cleanup_error);
      return 2;
    }

    vault.Store(L"bitunix-api-secret", "test-secret");
    const auto ready = quantara::EvaluateCredentialReadiness(root);
    if (ready != quantara::CredentialReadiness::kReady ||
        quantara::CredentialReadinessRequiresReconciliation(ready)) {
      std::filesystem::remove_all(root, cleanup_error);
      return 3;
    }

    vault.Remove(L"bitunix-api-key");
    const auto corrupt_path = root / L"bitunix-api-key.dpapi";
    std::ofstream corrupt(corrupt_path, std::ios::binary | std::ios::trunc);
    corrupt << "not-dpapi";
    corrupt.close();
    const auto invalid = quantara::EvaluateCredentialReadiness(root);
    if (invalid != quantara::CredentialReadiness::kInvalid ||
        !quantara::CredentialReadinessRequiresReconciliation(invalid)) {
      std::filesystem::remove_all(root, cleanup_error);
      return 4;
    }
  } catch (...) {
    std::filesystem::remove_all(root, cleanup_error);
    return 5;
  }

  std::filesystem::remove_all(root, cleanup_error);
  return 0;
}
