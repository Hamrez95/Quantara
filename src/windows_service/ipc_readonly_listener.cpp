#include "ipc_readonly_listener.h"

#include <windows.h>

#include "ipc_readonly_session.h"
#include "local_pipe_security.h"

namespace quantara {

bool RunReadOnlyStatusListener(
    HANDLE stop_event, const std::wstring& pipe_name,
    const std::atomic<ServiceSafetyState>& safety_state) noexcept {
  if (stop_event == nullptr || stop_event == INVALID_HANDLE_VALUE ||
      pipe_name.empty()) {
    return false;
  }

  try {
    RequestReplayGuard replay_guard;
    while (WaitForSingleObject(stop_event, 0) == WAIT_TIMEOUT) {
      HANDLE pipe = CreateLocalPipeServer(pipe_name);
      if (pipe == INVALID_HANDLE_VALUE) {
        return false;
      }

      const BOOL connected = ConnectNamedPipe(pipe, nullptr);
      const DWORD connect_error = connected ? ERROR_SUCCESS : GetLastError();
      const bool connection_ok =
          connected == TRUE || connect_error == ERROR_PIPE_CONNECTED;

      if (!connection_ok) {
        CloseHandle(pipe);
        if (connect_error == ERROR_OPERATION_ABORTED &&
            WaitForSingleObject(stop_event, 0) == WAIT_OBJECT_0) {
          return true;
        }
        return false;
      }

      if (WaitForSingleObject(stop_event, 0) == WAIT_OBJECT_0) {
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        return true;
      }

      const bool responded = ProcessAuthenticatedReadOnlyFrame(
          pipe, safety_state.load(std::memory_order_relaxed), replay_guard);
      if (responded) {
        FlushFileBuffers(pipe);
      }
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
    }
    return true;
  } catch (...) {
    return false;
  }
}

}  // namespace quantara
