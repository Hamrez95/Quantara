#pragma once

#include <filesystem>
#include <optional>
#include <vector>

#include "bitunix_reconciliation_facts_adapter.h"

namespace quantara {

// Service-owned durable recovery evidence. The payload is protected by the
// existing machine-DPAPI + hardened-DACL CredentialVault. Only facts that can
// identify/reconstruct a Quantara-owned position are persisted; current
// exchange protection is always recomputed from fresh exchange truth.
class RecoveryEvidenceVault final {
 public:
  explicit RecoveryEvidenceVault(std::filesystem::path root);

  // Replaces the complete evidence snapshot atomically. Invalid, duplicate or
  // authority-expanding records are rejected before anything is persisted.
  void Store(
      const std::vector<DurableReconciliationEvidence>& evidence) const;

  // Missing storage is a valid empty snapshot. Corrupt/tampered/unsupported
  // payloads return nullopt so callers can remain reconciliation-required.
  [[nodiscard]] std::optional<std::vector<DurableReconciliationEvidence>> Load()
      const noexcept;

 private:
  std::filesystem::path root_;
};

}  // namespace quantara
