#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "ipc_request_protocol.h"

namespace quantara {

enum class ServiceSafetyState {
  kDisarmed,
  kInterrupted,
  kReconciliationRequired,
};

std::optional<std::string> EncodeCanonicalReadOnlyResponse(
    const ReadOnlyRequest& request, ServiceSafetyState state) noexcept;

std::string_view ServiceSafetyStateName(ServiceSafetyState state) noexcept;

}  // namespace quantara
