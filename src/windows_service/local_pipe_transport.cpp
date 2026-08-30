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

  // ConnectNamedPipe can complete before the client writes its first frame.
  // Block for exactly one bounded message instead of peeking first; peeking can
  // report zero bytes during that legitimate scheduling window. In message
  // mode, a frame larger than this buffer fails ReadFile with ERROR_MORE_DATA,
  // so partial/oversized frames remain fail-closed.
  message.resize(kMaxAuthenticatedPipeMessageBytes);
  DWORD bytes_read = 0;
  const BOOL read_ok = ReadFile(pipe, message.data(),
                                kMaxAuthenticatedPipeMessageBytes, &bytes_read,
                                nullptr);
  if (!read_ok || bytes_read == 0 ||
      bytes_read > kMaxAuthenticatedPipeMessageBytes) {
    message.clear();
    return false;
  }

  message.resize(bytes_read);
  return true;
}

bool WriteLocalMessage(HANDLE pipe,
                       std::span<const std::uint8_t> message) noexcept {
  if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE || message.empty() ||
      message.size() > kMaxAuthenticatedPipeMessageBytes) {
    return false;
  }

  DWORD bytes_written = 0;
  const BOOL write_ok =
      WriteFile(pipe, message.data(), static_cast<DWORD>(message.size()),
                &bytes_written, nullptr);
  return write_ok == TRUE && bytes_written == message.size();
}

}  // namespace quantara
