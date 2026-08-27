#include "credential_readiness.h"

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
    if (quantara::EvaluateCredentialReadiness(root) !=
        quantara::CredentialReadiness::kMissing) {
      return 1;
    }

    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-api-key", "test-key");
    if (quantara::EvaluateCredentialReadiness(root) !=
        quantara::CredentialReadiness::kIncomplete) {
      std::filesystem::remove_all(root, cleanup_error);
      return 2;
    }

    vault.Store(L"bitunix-api-secret", "test-secret");
    if (quantara::EvaluateCredentialReadiness(root) !=
        quantara::CredentialReadiness::kReady) {
      std::filesystem::remove_all(root, cleanup_error);
      return 3;
    }

    vault.Remove(L"bitunix-api-key");
    const auto corrupt_path = root / L"bitunix-api-key.dpapi";
    std::ofstream corrupt(corrupt_path, std::ios::binary | std::ios::trunc);
    corrupt << "not-dpapi";
    corrupt.close();
    if (quantara::EvaluateCredentialReadiness(root) !=
        quantara::CredentialReadiness::kInvalid) {
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
