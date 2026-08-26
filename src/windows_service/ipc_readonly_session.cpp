#include "ipc_readonly_session.h"

#include <cstdint>
#include <vector>

#include "local_pipe_transport.h"

namespace quantara {

bool ProcessAuthenticatedReadOnlyFrame(HANDLE pipe, ServiceSafetyState state,
                                       RequestReplayGuard& replay_guard) noexcept {
  try {
    std::vector<std::uint8_t> message;
    if (!ReadAuthenticatedLocalMessage(pipe, message)) {
      return false;
    }

    const auto request = DecodeCanonicalReadOnlyRequest(message);
    if (!request.has_value() || !replay_guard.Accept(request->request_id)) {
      return false;
    }

    const auto response = EncodeCanonicalReadOnlyResponse(*request, state);
    if (!response.has_value()) {
      return false;
    }

    const auto* begin = reinterpret_cast<const std::uint8_t*>(response->data());
    return WriteLocalMessage(pipe, std::span<const std::uint8_t>(begin,
                                                                 response->size()));
  } catch (...) {
    return false;
  }
}

}  // namespace quantara
