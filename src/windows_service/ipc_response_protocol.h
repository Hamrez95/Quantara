#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "credential_readiness.h"
#include "ipc_request_protocol.h"

namespace quantara {

enum class ServiceSafetyState {
  kDisarmed,
  kInterrupted,
  kReconciliationRequired,
};

std::optional<std::string> EncodeCanonicalReadOnlyResponse(
    const ReadOnlyRequest& request, ServiceSafetyState state,
    CredentialReadiness credential_readiness) noexcept;

std::string_view ServiceSafetyStateName(ServiceSafetyState state) noexcept;
std::string_view CredentialReadinessName(CredentialReadiness readiness) noexcept;

}  // namespace quantara
