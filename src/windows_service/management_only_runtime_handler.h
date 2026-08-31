#pragma once

#include <ShlObj.h>
#include <windows.h>

#include <cmath>
#include <cctype>
#include <filesystem>
#include <optional>
#include <string_view>

#include "bitunix_exchange_truth_reader.h"
#include "bitunix_management_only_exchange_port.h"
#include "bitunix_reconciliation_facts_adapter.h"
#include "credential_readiness.h"
#include "ipc_request_protocol.h"
#include "management_only_worker_core.h"
#include "recovery_evidence_vault.h"
#include "../native/execution/management_only_mutation_executor.h"

namespace quantara {
namespace management_only_runtime_detail {

[[nodiscard]] inline ExistingPositionMutationExecutionResult Fail(
    std::string_view reason) noexcept {
  return {false, false, false, reason};
}

[[nodiscard]] inline bool IsCanonicalPositionId(
    std::string_view position_id) noexcept {
  if (position_id.empty() || position_id.size() > 64) return false;
  for (const unsigned char ch : position_id) {
    if (std::isdigit(ch) == 0) return false;
  }
  return position_id != "0";
}

[[nodiscard]] inline bool IsSupportedRequest(
    const ManagementOnlyRequest& request) noexcept {
  if (request.request_id.empty() ||
      !IsCanonicalPositionId(request.position_id)) {
    return false;
  }
  switch (request.kind) {
    case ManagementOnlyRequestKind::kCloseExistingPosition:
      return request.new_stop_price == 0.0;
    case ManagementOnlyRequestKind::kTightenExistingStop:
      return std::isfinite(request.new_stop_price) && request.new_stop_price > 0.0;
  }
  return false;
}

[[nodiscard]] inline std::optional<std::filesystem::path>
ProgramDataCredentialRoot() noexcept {
  PWSTR raw_path = nullptr;
  const HRESULT result =
      SHGetKnownFolderPath(FOLDERID_ProgramData, KF_FLAG_DEFAULT, nullptr,
                           &raw_path);
  if (FAILED(result) || raw_path == nullptr) {
    if (raw_path != nullptr) CoTaskMemFree(raw_path);
    return std::nullopt;
  }

  std::filesystem::path root(raw_path);
  CoTaskMemFree(raw_path);
  return root / L"Quantara" / L"ServiceCredentials";
}

}  // namespace management_only_runtime_detail

// Production Windows management-only IPC handler. It can only perform a full
// reduce-only close or tighten the stop of an already-verified existing Quantara
// position. Every invocation starts from fresh Bitunix positions/orders truth
// plus service-owned durable ownership evidence, re-evaluates the whole
// portfolio, passes through the shared mutation policy immediately before
// submission, and requires fresh exchange confirmation afterward. Tighten-stop
// preserves the exchange-derived current trigger semantic; the IPC caller cannot
// choose or guess it. No new-entry, leverage, margin, transfer, generic-order,
// stop-widening, or retry authority is exposed.
[[nodiscard]] inline ExistingPositionMutationExecutionResult
ExecuteWindowsManagementOnlyRequest(
    const ManagementOnlyRequest& request) noexcept {
  if (!management_only_runtime_detail::IsSupportedRequest(request)) {
    return management_only_runtime_detail::Fail("invalidManagementRequest");
  }

  const auto credential_root =
      management_only_runtime_detail::ProgramDataCredentialRoot();
  if (!credential_root.has_value() ||
      EvaluateCredentialReadiness(*credential_root) !=
          CredentialReadiness::kReady) {
    return management_only_runtime_detail::Fail("credentialsNotReady");
  }

  const auto positions_auth = GenerateBitunixReadOnlyAuthStamp();
  const auto orders_auth = GenerateBitunixReadOnlyAuthStamp();
  if (!positions_auth.has_value() || !orders_auth.has_value()) {
    return management_only_runtime_detail::Fail("exchangeAuthUnavailable");
  }

  const auto truth = ReadBitunixExchangeTruth(
      *credential_root, *positions_auth, *orders_auth);
  if (!truth.has_value()) {
    return management_only_runtime_detail::Fail("freshExchangeTruthUnavailable");
  }

  RecoveryEvidenceVault evidence_vault(*credential_root);
  const auto durable_evidence = evidence_vault.Load();
  if (!durable_evidence.has_value()) {
    return management_only_runtime_detail::Fail("durableEvidenceUnavailable");
  }

  WindowsManagementOnlyWorkerCore worker;
  const auto snapshot =
      worker.ReconcileFreshExchangeTruth(*truth, *durable_evidence);
  if (!snapshot.has_value() ||
      snapshot->mode != ManagementOnlyRecoveryMode::kManageExistingOnly ||
      !worker.CanManageExistingPositions() || worker.CanOpenNewEntry()) {
    return management_only_runtime_detail::Fail("managementAuthorityDenied");
  }

  const BitunixPendingPosition* target_position = nullptr;
  for (const auto& position : truth->positions) {
    if (position.position_id != request.position_id) continue;
    if (target_position != nullptr) {
      return management_only_runtime_detail::Fail("ambiguousExchangePosition");
    }
    target_position = &position;
  }
  if (target_position == nullptr) {
    return management_only_runtime_detail::Fail("exchangePositionNotFound");
  }

  const DurableReconciliationEvidence* target_evidence = nullptr;
  for (const auto& evidence : *durable_evidence) {
    if (evidence.position_id != request.position_id ||
        evidence.symbol != target_position->symbol) {
      continue;
    }
    if (target_evidence != nullptr) {
      return management_only_runtime_detail::Fail("ambiguousDurableEvidence");
    }
    target_evidence = &evidence;
  }
  if (target_evidence == nullptr) {
    return management_only_runtime_detail::Fail("durableEvidenceNotFound");
  }

  const auto current_evidence = ApplyCurrentExchangeProtectionEvidence(
      *target_position, *target_evidence, truth->pending_orders,
      truth->pending_tpsl_orders);
  if (!current_evidence.has_value()) {
    return management_only_runtime_detail::Fail("exchangeEvidenceJoinFailed");
  }

  const auto target_facts =
      BuildExistingExchangePositionFacts(*target_position, *current_evidence);
  if (!target_facts.has_value()) {
    return management_only_runtime_detail::Fail("exchangeEvidenceJoinFailed");
  }

  const ExistingPositionManagementDecision portfolio_decision{
      snapshot->classification,
      snapshot->authority,
      snapshot->blocks_new_entries,
      snapshot->reason,
  };

  ExistingPositionMutationRequest mutation{};
  mutation.position_id = target_facts->position_id;
  mutation.symbol = target_facts->symbol;
  mutation.reduce_only = true;
  mutation.increases_exposure = false;
  mutation.changes_margin_mode = false;
  mutation.widens_stop = false;

  switch (request.kind) {
    case ManagementOnlyRequestKind::kCloseExistingPosition:
      mutation.kind = ExistingPositionMutationKind::kReduceOnlyClose;
      break;
    case ManagementOnlyRequestKind::kTightenExistingStop:
      mutation.kind = ExistingPositionMutationKind::kTightenStop;
      mutation.new_stop_price = request.new_stop_price;
      mutation.stop_trigger_type = target_facts->current_stop_trigger_type;
      break;
  }

  BitunixManagementOnlyExchangePort exchange(*credential_root);
  return ExecuteExistingPositionMutation(portfolio_decision, *target_facts,
                                         mutation, exchange);
}

}  // namespace quantara
