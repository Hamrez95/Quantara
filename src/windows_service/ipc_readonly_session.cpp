#include "ipc_readonly_session.h"

#include <cstdint>
#include <string>
#include <vector>

#include "local_pipe_transport.h"

namespace quantara {
namespace {

bool WriteUtf8Message(HANDLE pipe, const std::string& response) noexcept {
  const auto* begin = reinterpret_cast<const std::uint8_t*>(response.data());
  return WriteLocalMessage(
      pipe, std::span<const std::uint8_t>(begin, response.size()));
}

std::string EncodeManagementResult(
    const ManagementOnlyRequest& request,
    const ExistingPositionMutationExecutionResult& result) {
  return "{\"protocolVersion\":1,\"requestId\":\"" + request.request_id +
         "\",\"kind\":\"managementResult\",\"payload\":{\"completed\":" +
         (result.completed ? "true" : "false") +
         ",\"submissionAttempted\":" +
         (result.submission_attempted ? "true" : "false") +
         ",\"exchangeTruthReconciled\":" +
         (result.exchange_truth_reconciled ? "true" : "false") + "}}";
}

}  // namespace

bool ProcessAuthenticatedFrame(
    HANDLE pipe, ServiceSafetyState state,
    CredentialReadiness credential_readiness, RequestReplayGuard& replay_guard,
    ManagementOnlyRequestHandler management_handler) noexcept {
  try {
    std::vector<std::uint8_t> message;
    if (!ReadAuthenticatedLocalMessage(pipe, message)) {
      return false;
    }

    if (const auto request = DecodeCanonicalReadOnlyRequest(message);
        request.has_value()) {
      if (!replay_guard.Accept(request->request_id)) {
        return false;
      }
      const auto response =
          EncodeCanonicalReadOnlyResponse(*request, state, credential_readiness);
      return response.has_value() && WriteUtf8Message(pipe, *response);
    }

    const auto management_request = DecodeCanonicalManagementOnlyRequest(message);
    if (!management_request.has_value() || management_handler == nullptr ||
        state != ServiceSafetyState::kManageExistingOnly ||
        !replay_guard.Accept(management_request->request_id)) {
      return false;
    }

    const auto result = management_handler(*management_request);
    return WriteUtf8Message(pipe,
                            EncodeManagementResult(*management_request, result));
  } catch (...) {
    return false;
  }
}

bool ProcessAuthenticatedReadOnlyFrame(
    HANDLE pipe, ServiceSafetyState state,
    CredentialReadiness credential_readiness,
    RequestReplayGuard& replay_guard) noexcept {
  return ProcessAuthenticatedFrame(pipe, state, credential_readiness,
                                   replay_guard, nullptr);
}

}  // namespace quantara
