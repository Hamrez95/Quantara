#pragma once

#include <windows.h>

#include "credential_readiness.h"
#include "ipc_request_protocol.h"
#include "ipc_response_protocol.h"

namespace quantara {

// Processes exactly one authenticated, read-only request/response exchange on
// an already-connected local named pipe. Invalid protocol frames, replayed
// request IDs and transport failures fail closed with no response. Credential
// readiness is metadata only: no secret material or execution authority is
// exposed through this boundary.
bool ProcessAuthenticatedReadOnlyFrame(
    HANDLE pipe, ServiceSafetyState state, CredentialReadiness credential_readiness,
    RequestReplayGuard& replay_guard) noexcept;

}  // namespace quantara
