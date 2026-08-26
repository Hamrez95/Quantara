#pragma once

#include <windows.h>

#include "ipc_request_protocol.h"
#include "ipc_response_protocol.h"

namespace quantara {

// Processes exactly one authenticated, read-only request/response exchange on
// an already-connected local named pipe. Invalid protocol frames, replayed
// request IDs and transport failures fail closed with no response. This grants
// no execution or mutation authority.
bool ProcessAuthenticatedReadOnlyFrame(HANDLE pipe, ServiceSafetyState state,
                                       RequestReplayGuard& replay_guard) noexcept;

}  // namespace quantara
