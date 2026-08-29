#pragma once

#include "bitunix_management_only_request.h"
#include "bitunix_request_authorizer.h"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace quantara {

struct BitunixManagementOnlyHttpEnvelope final {
  std::string host;
  std::string method;
  std::string resource;
  std::string body;
  std::vector<std::pair<std::string, std::string>> headers;
};

struct BitunixManagementOnlyHttpsLimits final {
  std::uint32_t connect_timeout_ms = 5000;
  std::uint32_t send_timeout_ms = 5000;
  std::uint32_t receive_timeout_ms = 5000;
  std::size_t max_body_bytes = 256 * 1024;
};

struct BitunixManagementOnlyHttpsResponse final {
  unsigned long status_code = 0;
  std::string body;
};

// Builds an authenticated HTTPS envelope for the one allowlisted management-only
// mutation supported by Windows today: reduce-only full close of an already
// verified position. No generic order/entry/margin endpoint can be represented.
[[nodiscard]] std::optional<BitunixManagementOnlyHttpEnvelope>
BuildBitunixManagementOnlyHttpEnvelope(
    const std::filesystem::path& credential_root,
    const BitunixManagementOnlyHttpRequest& request,
    std::string_view nonce,
    std::string_view timestamp) noexcept;

// Performs exactly one HTTPS POST to the allowlisted Bitunix close endpoint.
// Redirects are disabled, response size/time are bounded, and any validation,
// network, TLS, non-200, or body-bound failure returns nullopt. Callers must still
// reconcile fresh exchange truth; a 200 response is not execution confirmation.
[[nodiscard]] std::optional<BitunixManagementOnlyHttpsResponse>
ExecuteBitunixManagementOnlyHttps(
    const BitunixManagementOnlyHttpEnvelope& envelope,
    const BitunixManagementOnlyHttpsLimits& limits = {}) noexcept;

}  // namespace quantara
