#pragma once

#include <windows.h>

#include <cstdint>
#include <span>
#include <vector>

namespace quantara {

constexpr DWORD kMaxAuthenticatedPipeMessageBytes = 64 * 1024;

// Reads exactly one message-mode frame from an already-connected local pipe.
// The peer is authenticated from the Windows token before any bytes are
// accepted. Oversized/truncated frames fail closed. This transport grants no
// command or execution authority; callers must separately validate protocol
// version, message kind and replay/idempotency policy before interpreting the
// returned bytes.
bool ReadAuthenticatedLocalMessage(HANDLE pipe,
                                   std::vector<std::uint8_t>& message) noexcept;

// Writes exactly one already-validated response frame to a connected local
// pipe. Empty, oversized, partial or failed writes are rejected. This function
// performs no request parsing and grants no execution authority.
bool WriteLocalMessage(HANDLE pipe,
                       std::span<const std::uint8_t> message) noexcept;

}  // namespace quantara
