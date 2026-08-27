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

  // OpenProcessToken returns a primary token. CheckTokenMembership requires an
  // impersonation token when a non-null token handle is supplied, so using it
  // here silently rejects legitimate desktop peers running under a different
  // account from the LocalSystem service. Read enabled groups directly instead;
  // this preserves TOKEN_QUERY-only access and the same fail-closed semantics.
  DWORD required = 0;
  GetTokenInformation(token, TokenGroups, nullptr, 0, &required);
  if (required == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    return false;
  }

  std::vector<BYTE> groups_buffer(required);
  if (!GetTokenInformation(token, TokenGroups, groups_buffer.data(), required,
                           &required)) {
    return false;
  }

  const auto* groups =
      reinterpret_cast<const TOKEN_GROUPS*>(groups_buffer.data());
  for (DWORD index = 0; index < groups->GroupCount; ++index) {
    const SID_AND_ATTRIBUTES& group = groups->Groups[index];
    if (group.Sid == nullptr || !IsValidSid(group.Sid)) {
      continue;
    }
    const bool enabled = (group.Attributes & SE_GROUP_ENABLED) != 0;
    const bool deny_only = (group.Attributes & SE_GROUP_USE_FOR_DENY_ONLY) != 0;
    if (enabled && !deny_only && EqualSid(group.Sid, sid_buffer.data()) == TRUE) {
      return true;
    }
  }
  return false;
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

  // Resolve the connected client's PID from the named-pipe kernel object, then
  // inspect that process token directly. ImpersonateNamedPipeClient is tied to
  // the last message read and therefore cannot safely be the pre-read identity
  // gate for this transport.
  ULONG client_process_id = 0;
  if (!GetNamedPipeClientProcessId(pipe, &client_process_id) ||
      client_process_id == 0) {
    return false;
  }

  HANDLE client_process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, client_process_id);
  if (client_process == nullptr) {
    return false;
  }

  HANDLE token = nullptr;
  const bool token_opened =
      OpenProcessToken(client_process, TOKEN_QUERY, &token) == TRUE;
  CloseHandle(client_process);
  if (!token_opened) {
    return false;
  }

  ULONG verified_process_id = 0;
  const bool connection_unchanged =
      GetNamedPipeClientProcessId(pipe, &verified_process_id) == TRUE &&
      verified_process_id == client_process_id;

  // A real desktop client normally carries the Interactive SID. Hosted CI
  // runners may use a batch/service logon token instead, so also accept a peer
  // whose kernel-reported token user exactly matches this process user. The
  // pipe ACL remains local-only and no application/execution authority is
  // granted by successful transport authentication.
  const bool authenticated =
      connection_unchanged &&
      (IsSameUserAsServiceProcess(token) ||
       HasWellKnownMembership(token, WinInteractiveSid) ||
       HasWellKnownMembership(token, WinBuiltinAdministratorsSid));
  CloseHandle(token);
  return authenticated;
}

}  // namespace quantara
