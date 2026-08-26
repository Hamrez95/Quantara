#pragma once

#include <windows.h>

#include <atomic>
#include <string>

#include "ipc_response_protocol.h"

namespace quantara {

// Serves authenticated read-only status sessions on one local named-pipe name
// until stop_event is signaled. The caller owns the listener thread and may use
// CancelSynchronousIo on that thread during SCM stop/shutdown to interrupt a
// pending ConnectNamedPipe/ReadFile. Invalid client frames are dropped and do
// not grant mutation or execution authority.
bool RunReadOnlyStatusListener(
    HANDLE stop_event, const std::wstring& pipe_name,
    const std::atomic<ServiceSafetyState>& safety_state) noexcept;

}  // namespace quantara
