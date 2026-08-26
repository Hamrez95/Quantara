#include <iostream>
#include <string>

#include "ipc_response_protocol.h"

int wmain() {
  using quantara::ReadOnlyRequest;
  using quantara::ReadOnlyRequestKind;
  using quantara::ServiceSafetyState;

  const auto status = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"status-1", ReadOnlyRequestKind::kStatusRequest},
      ServiceSafetyState::kDisarmed);
  if (!status.has_value() ||
      *status !=
          "{\"protocolVersion\":1,\"requestId\":\"status-1\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"disarmed\",\"entryAuthority\":false}}") {
    std::wcerr << L"Disarmed status snapshot mismatch.\n";
    return 1;
  }

  const auto handshake = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"hello-1", ReadOnlyRequestKind::kHandshake},
      ServiceSafetyState::kReconciliationRequired);
  if (!handshake.has_value() ||
      *handshake !=
          "{\"protocolVersion\":1,\"requestId\":\"hello-1\",\"kind\":\"statusSnapshot\",\"payload\":{\"serviceState\":\"reconciliationRequired\",\"entryAuthority\":false}}") {
    std::wcerr << L"Handshake status snapshot mismatch.\n";
    return 1;
  }

  const auto interrupted = quantara::EncodeCanonicalReadOnlyResponse(
      ReadOnlyRequest{"status-2", ReadOnlyRequestKind::kStatusRequest},
      ServiceSafetyState::kInterrupted);
  if (!interrupted.has_value() ||
      interrupted->find("\"kind\":\"statusSnapshot\"") == std::string::npos ||
      interrupted->find("\"entryAuthority\":false") == std::string::npos ||
      interrupted->find("\"serviceState\":\"interrupted\"") == std::string::npos) {
    std::wcerr << L"Interrupted state must remain fail-closed.\n";
    return 1;
  }

  if (quantara::EncodeCanonicalReadOnlyResponse(
          ReadOnlyRequest{"", ReadOnlyRequestKind::kStatusRequest},
          ServiceSafetyState::kDisarmed)
          .has_value()) {
    std::wcerr << L"Empty request id was accepted.\n";
    return 1;
  }

  if (quantara::EncodeCanonicalReadOnlyResponse(
          ReadOnlyRequest{"unsafe\"id", ReadOnlyRequestKind::kStatusRequest},
          ServiceSafetyState::kDisarmed)
          .has_value()) {
    std::wcerr << L"Unsafe request id was accepted for JSON encoding.\n";
    return 1;
  }

  std::wcout << L"Quantara Windows read-only response self-test passed.\n";
  return 0;
}
