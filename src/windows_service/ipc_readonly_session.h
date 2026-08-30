#pragma once

#include <windows.h>

#include "credential_readiness.h"
#include "ipc_request_protocol.h"
#include "ipc_response_protocol.h"
#include "../native/execution/management_only_mutation_executor.h"

namespace quantara {

using ManagementOnlyRequestHandler = ExistingPositionMutationExecutionResult (*)(
    const ManagementOnlyRequest& request) noexcept;

// Processes exactly one authenticated request/response exchange on an
// already-connected local named pipe. Read-only requests remain available in
// every service safety state. The deliberately narrow management request can be
// dispatched only while the service is already publishing manageExistingOnly
// and only when an explicit runtime handler is attached. Invalid protocol
// frames, replayed request IDs and transport failures fail closed.
bool ProcessAuthenticatedFrame(
    HANDLE pipe, ServiceSafetyState state,
    CredentialReadiness credential_readiness, RequestReplayGuard& replay_guard,
    ManagementOnlyRequestHandler management_handler = nullptr) noexcept;

// Compatibility boundary for status-only listeners. Passing through this
// function never grants mutation authority because no management handler is
// attached.
bool ProcessAuthenticatedReadOnlyFrame(
    HANDLE pipe, ServiceSafetyState state,
    CredentialReadiness credential_readiness,
    RequestReplayGuard& replay_guard) noexcept;

}  // namespace quantara
