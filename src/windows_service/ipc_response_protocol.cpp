#include "ipc_response_protocol.h"

#include <string>

namespace quantara {

std::string_view ServiceSafetyStateName(ServiceSafetyState state) noexcept {
  switch (state) {
    case ServiceSafetyState::kDisarmed:
      return "disarmed";
    case ServiceSafetyState::kInterrupted:
      return "interrupted";
    case ServiceSafetyState::kReconciliationRequired:
      return "reconciliationRequired";
  }
  return "unknown";
}

std::optional<std::string> EncodeCanonicalReadOnlyResponse(
    const ReadOnlyRequest& request, ServiceSafetyState state) noexcept {
  try {
    const auto state_name = ServiceSafetyStateName(state);
    if (state_name == "unknown" || request.request_id.empty() ||
        request.request_id.size() > 64) {
      return std::nullopt;
    }

    const char* kind = nullptr;
    switch (request.kind) {
      case ReadOnlyRequestKind::kHandshake:
        kind = "handshakeResponse";
        break;
      case ReadOnlyRequestKind::kStatusRequest:
        kind = "statusResponse";
        break;
    }

    std::string response =
        "{\"protocolVersion\":1,\"requestId\":\"" + request.request_id +
        "\",\"kind\":\"" + kind +
        "\",\"payload\":{\"serviceState\":\"" + std::string(state_name) +
        "\",\"entryAuthority\":false}}";
    if (response.size() > kWindowsServiceMaxFrameBytes) {
      return std::nullopt;
    }
    return response;
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
