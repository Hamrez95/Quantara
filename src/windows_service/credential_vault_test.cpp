#include "credential_vault.h"

#include <Windows.h>
#include <aclapi.h>

#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void Require(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void AssertProtectedExplicitDacl(const std::filesystem::path& path) {
  PACL dacl = nullptr;
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  std::wstring mutable_path = path.wstring();
  const DWORD result = GetNamedSecurityInfoW(
      mutable_path.data(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION, nullptr,
      nullptr, &dacl, nullptr, &descriptor);
  if (result != ERROR_SUCCESS) {
    throw std::runtime_error("GetNamedSecurityInfoW failed with Win32 error " +
                             std::to_string(result));
  }

  try {
    Require(descriptor != nullptr, "Security descriptor is missing.");
    Require(dacl != nullptr, "Credential vault DACL is missing.");

    SECURITY_DESCRIPTOR_CONTROL control = 0;
    DWORD revision = 0;
    Require(GetSecurityDescriptorControl(descriptor, &control, &revision) != FALSE,
            "GetSecurityDescriptorControl failed.");
    Require((control & SE_DACL_PROTECTED) != 0,
            "Credential vault DACL must be protected from inheritance.");

    ACL_SIZE_INFORMATION information{};
    Require(GetAclInformation(dacl, &information, sizeof(information),
                              AclSizeInformation) != FALSE,
            "GetAclInformation failed.");
    Require(information.AceCount == 3,
            "Credential vault must contain exactly three explicit trustees.");

    for (DWORD index = 0; index < information.AceCount; ++index) {
      void* ace = nullptr;
      Require(GetAce(dacl, index, &ace) != FALSE, "GetAce failed.");
      const auto* header = static_cast<const ACE_HEADER*>(ace);
      Require(header->AceType == ACCESS_ALLOWED_ACE_TYPE,
              "Credential vault ACL must contain allow ACEs only.");
      Require((header->AceFlags & INHERITED_ACE) == 0,
              "Credential vault ACL must not contain inherited ACEs.");
    }
  } catch (...) {
    LocalFree(descriptor);
    throw;
  }

  LocalFree(descriptor);
}

std::filesystem::path UniqueVaultRoot() {
  wchar_t buffer[MAX_PATH]{};
  const DWORD length = GetTempPathW(MAX_PATH, buffer);
  Require(length > 0 && length < MAX_PATH, "GetTempPathW failed.");
  return std::filesystem::path(buffer) /
         (L"quantara-vault-acl-test-" + std::to_wstring(GetCurrentProcessId()));
}

}  // namespace

int wmain() {
  const auto root = UniqueVaultRoot();
  std::error_code cleanup_error;
  std::filesystem::remove_all(root, cleanup_error);

  try {
    quantara::CredentialVault vault(root);
    vault.Store(L"bitunix-test", "not-a-real-secret");

    const auto encrypted_path = root / L"bitunix-test.dpapi";
    Require(std::filesystem::exists(encrypted_path),
            "Credential vault did not create the encrypted payload.");
    AssertProtectedExplicitDacl(root);
    AssertProtectedExplicitDacl(encrypted_path);

    const auto loaded = vault.Load(L"bitunix-test");
    Require(loaded.has_value() && *loaded == "not-a-real-secret",
            "Credential vault DPAPI round-trip failed.");

    vault.Remove(L"bitunix-test");
    Require(!std::filesystem::exists(encrypted_path),
            "Credential vault remove left the encrypted payload behind.");
  } catch (const std::exception& error) {
    std::wcerr << L"Credential vault ACL test failed: " << error.what() << L'\n';
    std::filesystem::remove_all(root, cleanup_error);
    return 1;
  }

  std::filesystem::remove_all(root, cleanup_error);
  if (cleanup_error) {
    std::wcerr << L"Credential vault ACL test cleanup failed.\n";
    return 1;
  }

  std::wcout << L"Credential vault ACL test passed.\n";
  return 0;
}
