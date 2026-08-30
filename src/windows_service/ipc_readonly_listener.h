#pragma once

#include <windows.h>

#include <atomic>
#include <string>

#include "credential_readiness.h"
#include "ipc_readonly_session.h"
#include "ipc_response_protocol.h"

namespace quantara {

// Serves authenticated status/control sessions on one local named-pipe name
// until stop_event is signaled. Read-only requests remain available in every
// safety state. The deliberately narrow management request can be dispatched
// only when the caller explicitly supplies a management handler; the default
// remains nullptr so existing hosts stay fail-closed until runtime wiring is
// intentional. The caller owns the listener thread and may use
// CancelSynchronousIo on that thread during SCM stop/shutdown to interrupt a
// pending ConnectNamedPipe/ReadFile. Invalid client frames are dropped and do
// not grant mutation or execution authority. Credential readiness is exposed as
// bounded metadata only and never includes credential contents. When ready_event
// is supplied it is signaled only after the first local pipe instance has been
// created successfully, allowing the SCM host to avoid reporting Running
// prematurely.
bool RunReadOnlyStatusListener(
    HANDLE stop_event, const std::wstring& pipe_name,
    const std::atomic<ServiceSafetyState>& safety_state,
    const std::atomic<CredentialReadiness>& credential_readiness,
    HANDLE ready_event = nullptr,
    ManagementOnlyRequestHandler management_handler = nullptr) noexcept;

}  // namespace quantara
