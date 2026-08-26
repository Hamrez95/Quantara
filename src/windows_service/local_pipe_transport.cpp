#include "local_pipe_transport.h"

#include "local_pipe_security.h"

namespace quantara {

bool ReadAuthenticatedLocalMessage(HANDLE pipe,
                                   std::vector<std::uint8_t>& message) noexcept {
  message.clear();
  if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE) {
    return false;
  }
  if (!AuthenticateConnectedLocalPeer(pipe)) {
    return false;
  }

  DWORD available = 0;
  DWORD bytes_left_in_message = 0;
  if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available,
                     &bytes_left_in_message)) {
    return false;
  }
  if (available == 0 || bytes_left_in_message == 0 ||
      bytes_left_in_message > kMaxAuthenticatedPipeMessageBytes) {
    return false;
  }

  message.resize(bytes_left_in_message);
  DWORD bytes_read = 0;
  const BOOL read_ok = ReadFile(pipe, message.data(), bytes_left_in_message,
                                &bytes_read, nullptr);
  if (!read_ok || bytes_read != bytes_left_in_message) {
    message.clear();
    return false;
  }

  // Message-mode pipes preserve the frame boundary. Because the buffer is
  // sized from the current message length, a successful exact-length ReadFile
  // has consumed precisely one frame. Do not probe the pipe again here: the
  // peer may legitimately close immediately after sending, and that must not
  // turn a valid frame into a false failure.
  return true;
}

}  // namespace quantara
