#pragma once

#include <cstddef>
#include <optional>
#include <string>

#include "bitunix_readonly_request.h"

namespace quantara {

struct BitunixHttpsReadOnlyResponse final {
  unsigned long status_code;
  std::string body;
};

struct BitunixHttpsReadOnlyLimits final {
  unsigned long connect_timeout_ms = 5000;
  unsigned long send_timeout_ms = 5000;
  unsigned long receive_timeout_ms = 5000;
  std::size_t max_body_bytes = 512 * 1024;
};

// Revalidates the transport boundary independently from request construction.
// Only the pinned Bitunix futures host, HTTPS/443, GET, the two allowlisted
// reconciliation paths, and the five required private REST headers are accepted.
bool ValidateBitunixHttpsReadOnlyEnvelope(
    const BitunixReadOnlyHttpEnvelope& envelope) noexcept;

// Executes one bounded HTTPS GET for reconciliation truth. Redirects are
// disabled, response bodies are capped, only HTTP 200 is accepted, and any
// transport/protocol anomaly fails closed. This grants no mutation authority.
std::optional<BitunixHttpsReadOnlyResponse> ExecuteBitunixHttpsReadOnly(
    const BitunixReadOnlyHttpEnvelope& envelope,
    const BitunixHttpsReadOnlyLimits& limits = {}) noexcept;

}  // namespace quantara
