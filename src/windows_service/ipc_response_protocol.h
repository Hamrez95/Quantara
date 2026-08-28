#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "credential_readiness.h"
#include "ipc_request_protocol.h"
#include "../native/execution/management_only_recovery_coordinator.h"

namespace quantara {

enum class ServiceSafetyState {
  kDisarmed,
  kInterrupted,
  kReconciliationRequired,
  kManageExistingOnly,
};

std::optional<std::string> EncodeCanonicalReadOnlyResponse(
    const ReadOnlyRequest& request, ServiceSafetyState state,
    CredentialReadiness credential_readiness) noexcept;

std::string_view ServiceSafetyStateName(ServiceSafetyState state) noexcept;
std::string_view CredentialReadinessName(CredentialReadiness readiness) noexcept;

// Exposes management-only recovery state to the read-only IPC/status surface
// without turning it into entry authority. Ambiguous/unsupported combinations
// remain fail-closed.
ServiceSafetyState ServiceSafetyStateFromManagementOnlySnapshot(
    const ManagementOnlyRecoverySnapshot& snapshot) noexcept;

}  // namespace quantara
