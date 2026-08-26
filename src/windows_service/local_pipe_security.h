#pragma once

#include <windows.h>

#include <string>

namespace quantara {

// Creates one local-only message-mode named-pipe server instance with a DACL
// limited to LocalSystem, local administrators and interactive users.
// The caller must still authenticate the connected peer before processing any
// protocol frame.
HANDLE CreateLocalPipeServer(const std::wstring& pipe_name) noexcept;

// Authenticates a connected local named-pipe client using its kernel-backed
// Windows access token. Remote clients are rejected by the pipe itself; this
// additionally requires the local client token to be interactive or an
// enabled local administrator. No application-supplied identity is trusted.
bool AuthenticateConnectedLocalPeer(HANDLE pipe) noexcept;

}  // namespace quantara
