#include "recovery_evidence_vault.h"

#include "credential_vault.h"

#include <windows.h>

#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

quantara::DurableReconciliationEvidence Evidence(
    std::string position_id = "position-1",
    std::string symbol = "BTCUSDT") {
  quantara::DurableReconciliationEvidence item{};
  item.position_id = std::move(position_id);
  item.symbol = std::move(symbol);
  item.has_unambiguous_quantara_identity = true;
  item.has_complete_exchange_stop = true;  // Must not persist as current truth.
  item.has_complete_exchange_take_profit_ladder = true;
  item.has_conflicting_order_fill_or_history = false;
  item.has_durable_reconstruction = true;
  item.is_already_managed = true;
  item.expected_take_profit_order_count = 2;
  return item;
}

bool MissingVaultLoadsAsEmpty(const std::filesystem::path& root) {
  quantara::RecoveryEvidenceVault vault(root);
  const auto loaded = vault.Load();
  return loaded.has_value() && loaded->empty();
}

bool ValidEvidenceRoundTripsWithoutCachedProtection(
    const std::filesystem::path& root) {
  quantara::RecoveryEvidenceVault vault(root);
  vault.Store({Evidence()});
  const auto loaded = vault.Load();
  return loaded.has_value() && loaded->size() == 1 &&
         loaded->front().position_id == "position-1" &&
         loaded->front().symbol == "BTCUSDT" &&
         loaded->front().has_unambiguous_quantara_identity &&
         loaded->front().has_durable_reconstruction &&
         !loaded->front().has_conflicting_order_fill_or_history &&
         loaded->front().is_already_managed &&
         loaded->front().expected_take_profit_order_count == 2 &&
         !loaded->front().has_complete_exchange_stop &&
         !loaded->front().has_complete_exchange_take_profit_ladder;
}

bool InvalidEvidenceCannotBeStored(const std::filesystem::path& root) {
  quantara::RecoveryEvidenceVault vault(root);
  auto invalid = Evidence();
  invalid.has_unambiguous_quantara_identity = false;
  try {
    vault.Store({invalid});
  } catch (const std::invalid_argument&) {
    return true;
  }
  return false;
}

bool DuplicateIdentityCannotBeStored(const std::filesystem::path& root) {
  quantara::RecoveryEvidenceVault vault(root);
  try {
    vault.Store({Evidence(), Evidence()});
  } catch (const std::invalid_argument&) {
    return true;
  }
  return false;
}

bool MalformedProtectedPayloadFailsClosed(const std::filesystem::path& root) {
  quantara::CredentialVault raw(root);
  raw.Store(L"management-recovery-evidence-v1",
            "QRE1\nposition-1\tBTCUSDT\t1\t99\n");
  quantara::RecoveryEvidenceVault vault(root);
  return !vault.Load().has_value();
}

bool EmptyStoreRemovesEvidence(const std::filesystem::path& root) {
  quantara::RecoveryEvidenceVault vault(root);
  vault.Store({Evidence("position-2", "ETHUSDT")});
  vault.Store({});
  const auto loaded = vault.Load();
  return loaded.has_value() && loaded->empty();
}

}  // namespace

int wmain() {
  const auto root = std::filesystem::temp_directory_path() /
                    (L"quantara-recovery-evidence-vault-test-" +
                     std::to_wstring(GetCurrentProcessId()));
  std::error_code cleanup_error;
  std::filesystem::remove_all(root, cleanup_error);

  try {
    const bool passed = MissingVaultLoadsAsEmpty(root) &&
                        ValidEvidenceRoundTripsWithoutCachedProtection(root) &&
                        InvalidEvidenceCannotBeStored(root) &&
                        DuplicateIdentityCannotBeStored(root) &&
                        MalformedProtectedPayloadFailsClosed(root) &&
                        EmptyStoreRemovesEvidence(root);
    std::filesystem::remove_all(root, cleanup_error);
    if (!passed) {
      std::wcerr << L"Recovery evidence vault test failed.\n";
      return 1;
    }
    std::wcout << L"Recovery evidence vault test passed.\n";
    return 0;
  } catch (const std::exception& error) {
    std::filesystem::remove_all(root, cleanup_error);
    std::cerr << "Recovery evidence vault test threw: " << error.what() << "\n";
    return 1;
  }
}
