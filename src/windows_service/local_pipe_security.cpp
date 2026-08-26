#include "local_pipe_security.h"

#include <sddl.h>

#include <array>
#include <vector>

namespace quantara {
namespace {

constexpr wchar_t kPipePrefix[] = L"\\\\.\\pipe\\QuantaraExecutionService.";
constexpr size_t kPipePrefixLength =
    (sizeof(kPipePrefix) / sizeof(kPipePrefix[0])) - 1;
constexpr DWORD kPipeBufferBytes = 64 * 1024;

class LocalSecurityDescriptor final {
 public:
  LocalSecurityDescriptor() noexcept {
    constexpr wchar_t kPipeSddl[] =
        L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;IU)";
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            kPipeSddl, SDDL_REVISION_1, &descriptor, nullptr)) {
      return;
    }
    descriptor_ = descriptor;
    attributes_.nLength = sizeof(attributes_);
    attributes_.lpSecurityDescriptor = descriptor_;
    attributes_.bInheritHandle = FALSE;
  }

  ~LocalSecurityDescriptor() {
    if (descriptor_ != nullptr) {
      LocalFree(descriptor_);
    }
  }

  LocalSecurityDescriptor(const LocalSecurityDescriptor&) = delete;
  LocalSecurityDescriptor& operator=(const LocalSecurityDescriptor&) = delete;

  SECURITY_ATTRIBUTES* attributes() noexcept {
    return descriptor_ == nullptr ? nullptr : &attributes_;
  }

 private:
  PSECURITY_DESCRIPTOR descriptor_ = nullptr;
  SECURITY_ATTRIBUTES attributes_{};
};

bool HasWellKnownMembership(HANDLE token, WELL_KNOWN_SID_TYPE sid_type) noexcept {
  std::array<BYTE, SECURITY_MAX_SID_SIZE> sid_buffer{};
  DWORD sid_size = static_cast<DWORD>(sid_buffer.size());
  if (!CreateWellKnownSid(sid_type, nullptr, sid_buffer.data(), &sid_size)) {
    return false;
  }

  BOOL is_member = FALSE;
  if (!CheckTokenMembership(token, sid_buffer.data(), &is_member)) {
    return false;
  }
  return is_member == TRUE;
}

bool ReadTokenUserSid(HANDLE token, std::vector<BYTE>& buffer,
                      PSID& sid) noexcept {
  sid = nullptr;
  DWORD required = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &required);
  if (required == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    return false;
  }

  buffer.resize(required);
  if (!GetTokenInformation(token, TokenUser, buffer.data(), required,
                           &required)) {
    buffer.clear();
    return false;
  }

  const auto* token_user = reinterpret_cast<const TOKEN_USER*>(buffer.data());
  if (token_user->User.Sid == nullptr || !IsValidSid(token_user->User.Sid)) {
    buffer.clear();
    return false;
  }
  sid = token_user->User.Sid;
  return true;
}

bool IsSameUserAsServiceProcess(HANDLE peer_token) noexcept {
  HANDLE process_token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &process_token)) {
    return false;
  }

  std::vector<BYTE> peer_buffer;
  std::vector<BYTE> process_buffer;
  PSID peer_sid = nullptr;
  PSID process_sid = nullptr;
  const bool comparable = ReadTokenUserSid(peer_token, peer_buffer, peer_sid) &&
                          ReadTokenUserSid(process_token, process_buffer,
                                           process_sid);
  const bool same_user =
      comparable && EqualSid(peer_sid, process_sid) == TRUE;
  CloseHandle(process_token);
  return same_user;
}

bool IsAllowedPipeName(const std::wstring& pipe_name) noexcept {
  if (pipe_name.size() <= kPipePrefixLength) {
    return false;
  }
  return pipe_name.rfind(kPipePrefix, 0) == 0;
}

}  // namespace

HANDLE CreateLocalPipeServer(const std::wstring& pipe_name) noexcept {
  if (!IsAllowedPipeName(pipe_name)) {
    SetLastError(ERROR_INVALID_NAME);
    return INVALID_HANDLE_VALUE;
  }

  LocalSecurityDescriptor security;
  SECURITY_ATTRIBUTES* const attributes = security.attributes();
  if (attributes == nullptr) {
    return INVALID_HANDLE_VALUE;
  }

  return CreateNamedPipeW(
      pipe_name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT |
          PIPE_REJECT_REMOTE_CLIENTS,
      1, kPipeBufferBytes, kPipeBufferBytes, 0, attributes);
}

bool AuthenticateConnectedLocalPeer(HANDLE pipe) noexcept {
  if (pipe == nullptr || pipe == INVALID_HANDLE_VALUE) {
    return false;
  }

  ULONG client_process_id = 0;
  if (!GetNamedPipeClientProcessId(pipe, &client_process_id) ||
      client_process_id == 0) {
    return false;
  }

  if (!ImpersonateNamedPipeClient(pipe)) {
    return false;
  }

  HANDLE token = nullptr;
  bool authenticated = false;
  if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &token)) {
    // A real desktop client normally carries the Interactive SID. Hosted CI
    // runners may use a batch/service logon token instead, so also accept a
    // peer whose kernel-reported token user exactly matches this process user.
    // This remains local-only and authenticated; the pipe ACL still denies
    // anonymous/network clients and no application authority is granted here.
    authenticated = IsSameUserAsServiceProcess(token) ||
                    HasWellKnownMembership(token, WinInteractiveSid) ||
                    HasWellKnownMembership(token,
                                           WinBuiltinAdministratorsSid);
    CloseHandle(token);
  }

  if (!RevertToSelf()) {
    return false;
  }
  return authenticated;
}

}  // namespace quantara
