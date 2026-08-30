#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "ipc_request_protocol.h"
#include "ipc_response_protocol.h"
#include "service_shutdown_guard.h"

namespace {
std::vector<std::uint8_t> Frame(const std::string& text) {
  return std::vector<std::uint8_t>(text.begin(), text.end());
}
}  // namespace

int wmain() {
  using quantara::CredentialReadiness;
  using quantara::ExistingPositionClassification;
  using quantara::ExistingPositionManagementAuthority;
  using quantara::ManagementOnlyRecoveryMode;
  using quantara::ManagementOnlyRecoverySnapshot;
  using quantara::ReadOnlyRequest;
  using quantara::ReadOnlyRequestKind;
  using quantara::ServiceSafetyState;

  const auto status = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"status-1", ReadOnlyRequestKind::kStatusRequest},
      ServiceSafetyState::kDisarmed, CredentialReadiness::kReady);
  if (!status.has_value() ||
      *status !=
          "{\"protocolVersion\":1,\"requestId\":\"status-1\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"disarmed\",\"entryAuthority\":false}}") {
    std::wcerr << L"Disarmed status snapshot mismatch.\n";
    return 1;
  }

  const auto handshake = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"hello-1", ReadOnlyRequestKind::kHandshake},
      ServiceSafetyState::kReconciliationRequired,
      CredentialReadiness::kInvalid);
  if (!handshake.has_value() ||
      *handshake !=
          "{\"protocolVersion\":1,\"requestId\":\"hello-1\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"reconciliationRequired\",\"entryAuthority\":false}}") {
    std::wcerr << L"Handshake status snapshot mismatch.\n";
    return 1;
  }

  const auto interrupted = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"status-2", ReadOnlyRequestKind::kStatusRequest},
      ServiceSafetyState::kInterrupted, CredentialReadiness::kMissing);
  if (!interrupted.has_value() ||
      interrupted->find("\"kind\":\"statusSnapshot\"") == std::string::npos ||
      interrupted->find("\"entryAuthority\":false") == std::string::npos ||
      interrupted->find("\"serviceState\":\"interrupted\"") == std::string::npos) {
    std::wcerr << L"Interrupted state must remain fail-closed.\n";
    return 1;
  }

  if (quantara::ServiceSafetyStateForStopBoundary() !=
          ServiceSafetyState::kInterrupted ||
      quantara::ShouldPublishReconciliationResult(true, false) ||
      quantara::ShouldPublishReconciliationResult(false, true) ||
      !quantara::ShouldPublishReconciliationResult(false, false)) {
    std::wcerr << L"Stop/shutdown reconciliation guard mismatch.\n";
    return 1;
  }

  const ManagementOnlyRecoverySnapshot manage_existing{
      ManagementOnlyRecoveryMode::kManageExistingOnly,
      ExistingPositionClassification::kManaged,
      ExistingPositionManagementAuthority::kManageExistingOnly,
      true,
      "allManagedVerified"};
  if (quantara::ServiceSafetyStateFromManagementOnlySnapshot(manage_existing) !=
      ServiceSafetyState::kReconciliationRequired) {
    std::wcerr << L"Verified recovery must not claim management before the runtime executor is attached.\n";
    return 1;
  }
  if (quantara::ServiceSafetyStateFromManagementOnlySnapshot(manage_existing, true) !=
      ServiceSafetyState::kManageExistingOnly) {
    std::wcerr << L"Attached management-only executor state mapping mismatch.\n";
    return 1;
  }
  const auto management_status = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"status-managed", ReadOnlyRequestKind::kStatusRequest},
      ServiceSafetyState::kManageExistingOnly, CredentialReadiness::kReady);
  if (!management_status.has_value() ||
      management_status->find("\"serviceState\":\"manageExistingOnly\"") ==
          std::string::npos ||
      management_status->find("\"entryAuthority\":false") ==
          std::string::npos) {
    std::wcerr << L"Management-only status must never imply entry authority.\n";
    return 1;
  }

  const ManagementOnlyRecoverySnapshot reconcile_required{
      ManagementOnlyRecoveryMode::kReconciliationRequired,
      ExistingPositionClassification::kAmbiguous,
      ExistingPositionManagementAuthority::kReconciliationOnly,
      true,
      "freshExchangeTruthRequired"};
  if (quantara::ServiceSafetyStateFromManagementOnlySnapshot(
          reconcile_required) != ServiceSafetyState::kReconciliationRequired) {
    std::wcerr << L"Reconciliation-required worker state mapping mismatch.\n";
    return 1;
  }

  const ManagementOnlyRecoverySnapshot inconsistent{
      ManagementOnlyRecoveryMode::kManageExistingOnly,
      ExistingPositionClassification::kManaged,
      ExistingPositionManagementAuthority::kManageExistingOnly,
      false,
      "invalid"};
  if (quantara::ServiceSafetyStateFromManagementOnlySnapshot(inconsistent) !=
      ServiceSafetyState::kDisarmed) {
    std::wcerr << L"Inconsistent management authority must fail closed.\n";
    return 1;
  }

  const ManagementOnlyRecoverySnapshot external_with_invalid_authority{
      ManagementOnlyRecoveryMode::kManageExistingOnly,
      ExistingPositionClassification::kExternalUnmanaged,
      ExistingPositionManagementAuthority::kManageExistingOnly,
      true,
      "invalidExternalAuthority"};
  if (quantara::ServiceSafetyStateFromManagementOnlySnapshot(
          external_with_invalid_authority) != ServiceSafetyState::kDisarmed) {
    std::wcerr << L"External positions must never map to management authority.\n";
    return 1;
  }

  const ManagementOnlyRecoverySnapshot ambiguous_with_invalid_authority{
      ManagementOnlyRecoveryMode::kManageExistingOnly,
      ExistingPositionClassification::kAmbiguous,
      ExistingPositionManagementAuthority::kManageExistingOnly,
      true,
      "invalidAmbiguousAuthority"};
  if (quantara::ServiceSafetyStateFromManagementOnlySnapshot(
          ambiguous_with_invalid_authority) != ServiceSafetyState::kDisarmed) {
    std::wcerr << L"Ambiguous positions must never map to management authority.\n";
    return 1;
  }

  const auto credential = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"credential-1",
                      ReadOnlyRequestKind::kCredentialReadinessRequest},
      ServiceSafetyState::kDisarmed, CredentialReadiness::kIncomplete);
  if (!credential.has_value() ||
      *credential !=
          "{\"protocolVersion\":1,\"requestId\":\"credential-1\",\"kind\":\"credentialReadinessSnapshot\",\"payload\":{\"credentialReadiness\":\"incomplete\",\"entryAuthority\":false}}" ||
      credential->find("secret") != std::string::npos ||
      credential->find("api") != std::string::npos) {
    std::wcerr << L"Credential readiness snapshot must remain metadata-only.\n";
    return 1;
  }

  if (quantara::EncodeCanonicalReadOnlyResponse(
          ReadOnlyRequest{"", ReadOnlyRequestKind::kStatusRequest},
          ServiceSafetyState::kDisarmed, CredentialReadiness::kMissing)
          .has_value()) {
    std::wcerr << L"Empty request id was accepted.\n";
    return 1;
  }

  if (quantara::EncodeCanonicalReadOnlyResponse(
          ReadOnlyRequest{"unsafe\"id", ReadOnlyRequestKind::kStatusRequest},
          ServiceSafetyState::kDisarmed, CredentialReadiness::kMissing)
          .has_value()) {
    std::wcerr << L"Unsafe request id was accepted for JSON encoding.\n";
    return 1;
  }

  const auto close = quantara::DecodeCanonicalManagementOnlyRequest(Frame(
      "{\"protocolVersion\":1,\"requestId\":\"close-1\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"123456789\"}}"));
  if (!close.has_value() || close->request_id != "close-1" ||
      close->position_id != "123456789" ||
      close->kind != quantara::ManagementOnlyRequestKind::kCloseExistingPosition) {
    std::wcerr << L"Canonical management-only close request was not decoded.\n";
    return 1;
  }

  const std::string unsafe_frames[] = {
      "{\"protocolVersion\":1,\"requestId\":\"close-2\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"abc\"}}",
      "{\"protocolVersion\":1,\"requestId\":\"close-3\",\"kind\":\"openPosition\",\"payload\":{\"positionId\":\"123\"}}",
      "{\"protocolVersion\":1,\"requestId\":\"close-4\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"123\",\"leverage\":100}}",
      "{\"protocolVersion\":1,\"requestId\":\"unsafe\\\"id\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"123\"}}",
  };
  for (const auto& unsafe : unsafe_frames) {
    if (quantara::DecodeCanonicalManagementOnlyRequest(Frame(unsafe)).has_value()) {
      std::wcerr << L"Unsafe or non-canonical management IPC frame was accepted.\n";
      return 1;
    }
  }

  std::wcout << L"Quantara Windows read-only response self-test passed.\n";
  return 0;
}
