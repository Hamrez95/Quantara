#include "ipc_response_protocol.h"

#include <string>

namespace quantara {
namespace {

bool IsSafeResponseRequestId(std::string_view value) noexcept {
  if (value.empty() || value.size() > 64) {
    return false;
  }
  for (const char ch : value) {
    const bool safe = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                      (ch >= '0' && ch <= '9') || ch == '.' || ch == '_' ||
                      ch == '-';
    if (!safe) {
      return false;
    }
  }
  return true;
}

}  // namespace

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
    if (state_name == "unknown" || !IsSafeResponseRequestId(request.request_id)) {
      return std::nullopt;
    }

    switch (request.kind) {
      case ReadOnlyRequestKind::kHandshake:
      case ReadOnlyRequestKind::kStatusRequest:
        break;
    }

    std::string response =
        "{\"protocolVersion\":1,\"requestId\":\"" + request.request_id +
        "\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"" +
        std::string(state_name) +
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
