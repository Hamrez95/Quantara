#include "ipc_response_protocol.h"

#include <string>

namespace quantara {
namespace {

bool IsSafeResponseRequestId(std::string_view value) noexcept {
  if (value.empty() || value.size() > 64) {
    return false;
  }
  for (const char ch : value) {
    const bool safe = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                      (ch >= '0' && ch <= '9') || ch == '.' || ch == '_' ||
                      ch == '-';
    if (!safe) {
      return false;
    }
  }
  return true;
}

}  // namespace

std::string_view ServiceSafetyStateName(ServiceSafetyState state) noexcept {
  switch (state) {
    case ServiceSafetyState::kDisarmed:
      return "disarmed";
    case ServiceSafetyState::kInterrupted:
      return "interrupted";
    case ServiceSafetyState::kReconciliationRequired:
      return "reconciliationRequired";
    case ServiceSafetyState::kManageExistingOnly:
      return "manageExistingOnly";
  }
  return "unknown";
}

ServiceSafetyState ServiceSafetyStateFromManagementOnlySnapshot(
    const ManagementOnlyRecoverySnapshot& snapshot) noexcept {
  if (snapshot.mode == ManagementOnlyRecoveryMode::kManageExistingOnly &&
      snapshot.authority ==
          ExistingPositionManagementAuthority::kManageExistingOnly &&
      snapshot.blocks_new_entries) {
    return ServiceSafetyState::kManageExistingOnly;
  }
  if (snapshot.mode == ManagementOnlyRecoveryMode::kReconciliationRequired ||
      snapshot.authority ==
          ExistingPositionManagementAuthority::kReconciliationOnly) {
    return ServiceSafetyState::kReconciliationRequired;
  }
  return ServiceSafetyState::kDisarmed;
}

std::string_view CredentialReadinessName(CredentialReadiness readiness) noexcept {
  switch (readiness) {
    case CredentialReadiness::kMissing:
      return "missing";
    case CredentialReadiness::kReady:
      return "ready";
    case CredentialReadiness::kIncomplete:
      return "incomplete";
    case CredentialReadiness::kInvalid:
      return "invalid";
  }
  return "unknown";
}

std::optional<std::string> EncodeCanonicalReadOnlyResponse(
    const ReadOnlyRequest& request, ServiceSafetyState state,
    CredentialReadiness credential_readiness) noexcept {
  try {
    if (!IsSafeResponseRequestId(request.request_id)) {
      return std::nullopt;
    }

    std::string response;
    switch (request.kind) {
      case ReadOnlyRequestKind::kHandshake:
      case ReadOnlyRequestKind::kStatusRequest: {
        const auto state_name = ServiceSafetyStateName(state);
        if (state_name == "unknown") {
          return std::nullopt;
        }
        response =
            "{\"protocolVersion\":1,\"requestId\":\"" + request.request_id +
            "\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"" +
            std::string(state_name) +
            "\",\"entryAuthority\":false}}";
        break;
      }
      case ReadOnlyRequestKind::kCredentialReadinessRequest: {
        const auto readiness_name = CredentialReadinessName(credential_readiness);
        if (readiness_name == "unknown") {
          return std::nullopt;
        }
        response =
            "{\"protocolVersion\":1,\"requestId\":\"" + request.request_id +
            "\",\"kind\":\"credentialReadinessSnapshot\",\"payload\":{\"credentialReadiness\":\"" +
            std::string(readiness_name) +
            "\",\"entryAuthority\":false}}";
        break;
      }
    }

    if (response.size() > kWindowsServiceMaxFrameBytes) {
      return std::nullopt;
    }
    return response;
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
