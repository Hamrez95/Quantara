#pragma once

#include <windows.h>

#include <cstdint>
#include <vector>

namespace quantara {

constexpr DWORD kMaxAuthenticatedPipeMessageBytes = 64 * 1024;

// Reads exactly one message-mode frame from an already-connected local pipe.
// The peer is authenticated from the Windows token before any bytes are
// accepted. Oversized/truncated frames fail closed. This transport grants no
// command or execution authority; callers must separately validate protocol
// version, message kind and replay/idempotency policy.
bool ReadAuthenticatedLocalMessage(HANDLE pipe,
                                   std::vector<std::uint8_t>& message) noexcept;

}  // namespace quantara
