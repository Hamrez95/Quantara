#include "ipc_readonly_listener.h"

#include <windows.h>

#include "ipc_readonly_session.h"
#include "local_pipe_security.h"
#include "network_change_monitor.h"

namespace quantara {
namespace {

bool WaitForClientOrStop(HANDLE pipe, HANDLE stop_event) noexcept {
  DWORD mode = PIPE_READMODE_MESSAGE | PIPE_NOWAIT;
  if (!SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr)) {
    return false;
  }

  while (WaitForSingleObject(stop_event, 0) == WAIT_TIMEOUT) {
    const BOOL connected = ConnectNamedPipe(pipe, nullptr);
    if (connected == TRUE) {
      mode = PIPE_READMODE_MESSAGE | PIPE_WAIT;
      return SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr) == TRUE;
    }

    const DWORD error = GetLastError();
    if (error == ERROR_PIPE_CONNECTED) {
      mode = PIPE_READMODE_MESSAGE | PIPE_WAIT;
      return SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr) == TRUE;
    }
    if (error != ERROR_PIPE_LISTENING && error != ERROR_NO_DATA) {
      return false;
    }
    Sleep(10);
  }
  return false;
}

}  // namespace

bool RunReadOnlyStatusListener(
    HANDLE stop_event, const std::wstring& pipe_name,
    std::atomic<ServiceSafetyState>& safety_state) noexcept {
  if (stop_event == nullptr || stop_event == INVALID_HANDLE_VALUE ||
      pipe_name.empty()) {
    return false;
  }

  try {
    NetworkChangeMonitor network_monitor(safety_state);
    if (!network_monitor.Start()) {
      return false;
    }

    RequestReplayGuard replay_guard;
    while (WaitForSingleObject(stop_event, 0) == WAIT_TIMEOUT) {
      HANDLE pipe = CreateLocalPipeServer(pipe_name);
      if (pipe == INVALID_HANDLE_VALUE) {
        return false;
      }

      const bool connection_ok = WaitForClientOrStop(pipe, stop_event);
      if (!connection_ok) {
        CloseHandle(pipe);
        return WaitForSingleObject(stop_event, 0) == WAIT_OBJECT_0;
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
