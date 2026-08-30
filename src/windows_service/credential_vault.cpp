#include "credential_vault.h"

#include <Windows.h>
#include <aclapi.h>
#include <dpapi.h>

#include <array>
#include <fstream>
#include <stdexcept>
#include <utility>
#include <vector>

namespace quantara {
namespace {

void ValidateName(const std::wstring& name) {
  if (name.empty() || name.size() > 64) {
    throw std::invalid_argument("Credential name is invalid.");
  }
  for (const wchar_t ch : name) {
    const bool safe = (ch >= L'a' && ch <= L'z') || (ch >= L'A' && ch <= L'Z') ||
                      (ch >= L'0' && ch <= L'9') || ch == L'-' || ch == L'_';
    if (!safe) {
      throw std::invalid_argument("Credential name contains unsafe characters.");
    }
  }
}

std::runtime_error Win32Error(const char* operation) {
  return std::runtime_error(std::string(operation) + " failed with Win32 error " +
                            std::to_string(GetLastError()));
}

std::runtime_error Win32CodeError(const char* operation, DWORD error) {
  return std::runtime_error(std::string(operation) + " failed with Win32 error " +
                            std::to_string(error));
}

std::vector<BYTE> ReadCurrentUserSid() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    throw Win32Error("OpenProcessToken");
  }

  DWORD required = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &required);
  if (required == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    CloseHandle(token);
    throw Win32Error("GetTokenInformation size");
  }

  std::vector<BYTE> token_user_buffer(required);
  if (!GetTokenInformation(token, TokenUser, token_user_buffer.data(), required,
                           &required)) {
    CloseHandle(token);
    throw Win32Error("GetTokenInformation user");
  }
  CloseHandle(token);

  const auto* token_user =
      reinterpret_cast<const TOKEN_USER*>(token_user_buffer.data());
  if (token_user->User.Sid == nullptr || !IsValidSid(token_user->User.Sid)) {
    throw std::runtime_error("Current Windows user SID is invalid.");
  }

  const DWORD sid_length = GetLengthSid(token_user->User.Sid);
  std::vector<BYTE> sid(sid_length);
  if (!CopySid(sid_length, sid.data(), token_user->User.Sid)) {
    throw Win32Error("CopySid");
  }
  return sid;
}

std::array<BYTE, SECURITY_MAX_SID_SIZE> CreateKnownSid(
    WELL_KNOWN_SID_TYPE type, DWORD& sid_size) {
  std::array<BYTE, SECURITY_MAX_SID_SIZE> sid{};
  sid_size = static_cast<DWORD>(sid.size());
  if (!CreateWellKnownSid(type, nullptr, sid.data(), &sid_size)) {
    throw Win32Error("CreateWellKnownSid");
  }
  return sid;
}

void HardenPathDacl(const std::filesystem::path& path, bool directory) {
  auto current_user = ReadCurrentUserSid();
  DWORD system_size = 0;
  DWORD admins_size = 0;
  auto system_sid = CreateKnownSid(WinLocalSystemSid, system_size);
  auto admins_sid = CreateKnownSid(WinBuiltinAdministratorsSid, admins_size);

  const DWORD inheritance =
      directory ? SUB_CONTAINERS_AND_OBJECTS_INHERIT : NO_INHERITANCE;
  std::array<EXPLICIT_ACCESSW, 3> access{};
  const std::array<PSID, 3> trustees = {
      reinterpret_cast<PSID>(current_user.data()),
      reinterpret_cast<PSID>(system_sid.data()),
      reinterpret_cast<PSID>(admins_sid.data()),
  };

  for (size_t index = 0; index < access.size(); ++index) {
    access[index].grfAccessPermissions = FILE_ALL_ACCESS;
    access[index].grfAccessMode = SET_ACCESS;
    access[index].grfInheritance = inheritance;
    access[index].Trustee.TrusteeForm = TRUSTEE_IS_SID;
    access[index].Trustee.TrusteeType = TRUSTEE_IS_USER;
    access[index].Trustee.ptstrName =
        reinterpret_cast<LPWSTR>(trustees[index]);
  }

  PACL acl = nullptr;
  const DWORD acl_error = SetEntriesInAclW(
      static_cast<ULONG>(access.size()), access.data(), nullptr, &acl);
  if (acl_error != ERROR_SUCCESS) {
    throw Win32CodeError("SetEntriesInAclW", acl_error);
  }

  std::wstring mutable_path = path.wstring();
  const DWORD security_error = SetNamedSecurityInfoW(
      mutable_path.data(), SE_FILE_OBJECT,
      DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, nullptr,
      nullptr, acl, nullptr);
  LocalFree(acl);
  if (security_error != ERROR_SUCCESS) {
    throw Win32CodeError("SetNamedSecurityInfoW", security_error);
  }
}

}  // namespace

CredentialVault::CredentialVault(std::filesystem::path root) : root_(std::move(root)) {
  if (root_.empty()) {
    throw std::invalid_argument("Credential vault root is required.");
  }
}

std::filesystem::path CredentialVault::PathFor(const std::wstring& name) const {
  ValidateName(name);
  return root_ / (name + L".dpapi");
}

void CredentialVault::Store(const std::wstring& name, const std::string& secret) const {
  if (secret.empty() || secret.size() > 16 * 1024) {
    throw std::invalid_argument("Credential secret size is invalid.");
  }

  DATA_BLOB input{};
  input.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(secret.data()));
  input.cbData = static_cast<DWORD>(secret.size());
  DATA_BLOB output{};

  if (!CryptProtectData(&input, L"Quantara Windows Service credential", nullptr, nullptr, nullptr,
                        CRYPTPROTECT_LOCAL_MACHINE | CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    throw Win32Error("CryptProtectData");
  }

  const auto path = PathFor(name);
  std::filesystem::create_directories(root_);
  const auto temporary = std::filesystem::path(path.wstring() + L".tmp");
  try {
    HardenPathDacl(root_, true);

    std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
    if (!stream) {
      throw std::runtime_error("Credential vault temporary file could not be opened.");
    }
    stream.write(reinterpret_cast<const char*>(output.pbData), output.cbData);
    stream.close();
    if (!stream) {
      throw std::runtime_error("Credential vault write failed.");
    }

    HardenPathDacl(temporary, false);
    if (!MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
      throw Win32Error("MoveFileExW credential replacement");
    }
  } catch (...) {
    DeleteFileW(temporary.c_str());
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    throw;
  }
  SecureZeroMemory(output.pbData, output.cbData);
  LocalFree(output.pbData);
}

std::optional<std::string> CredentialVault::Load(const std::wstring& name) const {
  const auto path = PathFor(name);
  if (!std::filesystem::exists(path)) {
    return std::nullopt;
  }

  std::ifstream stream(path, std::ios::binary | std::ios::ate);
  if (!stream) {
    throw std::runtime_error("Credential vault file could not be opened.");
  }
  const auto size = stream.tellg();
  if (size <= 0 || size > 64 * 1024) {
    throw std::runtime_error("Credential vault payload size is invalid.");
  }
  std::vector<BYTE> encrypted(static_cast<size_t>(size));
  stream.seekg(0);
  stream.read(reinterpret_cast<char*>(encrypted.data()), size);
  if (!stream) {
    throw std::runtime_error("Credential vault read failed.");
  }

  DATA_BLOB input{static_cast<DWORD>(encrypted.size()), encrypted.data()};
  DATA_BLOB output{};
  if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                          &output)) {
    throw Win32Error("CryptUnprotectData");
  }

  std::string secret(reinterpret_cast<const char*>(output.pbData), output.cbData);
  SecureZeroMemory(output.pbData, output.cbData);
  LocalFree(output.pbData);
  return secret;
}

void CredentialVault::Remove(const std::wstring& name) const {
  const auto path = PathFor(name);
  std::error_code error;
  const bool removed = std::filesystem::remove(path, error);
  if (error) {
    throw std::runtime_error("Credential vault delete failed.");
  }
  (void)removed;
}

}  // namespace quantara
