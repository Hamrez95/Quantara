#include <windows.h>
#include <ShlObj.h>

#include <array>
#include <filesystem>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

#include "credential_vault.h"

namespace {

constexpr wchar_t kApiKeyName[] = L"bitunix-api-key";
constexpr wchar_t kApiSecretName[] = L"bitunix-api-secret";
constexpr std::size_t kMaxSecretBytes = 16 * 1024;

enum class Command {
  kStoreApiKey,
  kStoreApiSecret,
  kRemoveAll,
  kStatus,
  kSelfTest,
};

std::optional<Command> ParseCommand(std::wstring_view value) noexcept {
  if (value == L"--store-api-key") {
    return Command::kStoreApiKey;
  }
  if (value == L"--store-api-secret") {
    return Command::kStoreApiSecret;
  }
  if (value == L"--remove-all") {
    return Command::kRemoveAll;
  }
  if (value == L"--status") {
    return Command::kStatus;
  }
  if (value == L"--self-test") {
    return Command::kSelfTest;
  }
  return std::nullopt;
}

bool IsElevatedAdministrator() noexcept {
  SID_IDENTIFIER_AUTHORITY authority = SECURITY_NT_AUTHORITY;
  PSID administrators = nullptr;
  if (!AllocateAndInitializeSid(
          &authority, 2, SECURITY_BUILTIN_DOMAIN_RID,
          DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &administrators)) {
    return false;
  }

  BOOL member = FALSE;
  const BOOL checked = CheckTokenMembership(nullptr, administrators, &member);
  FreeSid(administrators);
  return checked == TRUE && member == TRUE;
}

std::filesystem::path ProgramDataCredentialRoot() {
  PWSTR raw_path = nullptr;
  const HRESULT result =
      SHGetKnownFolderPath(FOLDERID_ProgramData, KF_FLAG_DEFAULT, nullptr,
                           &raw_path);
  if (FAILED(result) || raw_path == nullptr) {
    if (raw_path != nullptr) {
      CoTaskMemFree(raw_path);
    }
    throw std::runtime_error("Windows ProgramData could not be resolved.");
  }

  std::filesystem::path root(raw_path);
  CoTaskMemFree(raw_path);
  return root / L"Quantara" / L"ServiceCredentials";
}

void RejectReparsePointIfPresent(const std::filesystem::path& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = GetLastError();
    if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
      return;
    }
    throw std::runtime_error("Credential path attributes could not be read.");
  }
  if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    throw std::runtime_error("Credential path cannot be a reparse point.");
  }
}

void GuardProductionPath(const std::filesystem::path& root) {
  RejectReparsePointIfPresent(root.parent_path());
  RejectReparsePointIfPresent(root);
}

std::string ReadSecretFromRedirectedStdin() {
  const HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
  if (input == nullptr || input == INVALID_HANDLE_VALUE) {
    throw std::runtime_error("Credential input is unavailable.");
  }

  SetLastError(ERROR_SUCCESS);
  const DWORD type = GetFileType(input);
  if (type == FILE_TYPE_UNKNOWN && GetLastError() != ERROR_SUCCESS) {
    throw std::runtime_error("Credential input type could not be verified.");
  }
  if (type == FILE_TYPE_CHAR) {
    throw std::runtime_error(
        "Interactive credential input is refused; provide the secret through redirected standard input.");
  }

  std::string secret;
  secret.reserve(kMaxSecretBytes);
  std::array<char, 4096> buffer{};
  while (std::cin.good()) {
    std::cin.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
    const auto count = std::cin.gcount();
    if (count <= 0) {
      break;
    }
    if (secret.size() + static_cast<std::size_t>(count) >
        kMaxSecretBytes + 2) {
      SecureZeroMemory(secret.data(), secret.size());
      throw std::runtime_error("Credential input exceeds the bounded limit.");
    }
    secret.append(buffer.data(), static_cast<std::size_t>(count));
  }
  if (std::cin.bad()) {
    SecureZeroMemory(secret.data(), secret.size());
    throw std::runtime_error("Credential input could not be read.");
  }

  if (!secret.empty() && secret.back() == '\n') {
    secret.pop_back();
    if (!secret.empty() && secret.back() == '\r') {
      secret.pop_back();
    }
  }

  if (secret.empty() || secret.size() > kMaxSecretBytes ||
      secret.find('\0') != std::string::npos) {
    SecureZeroMemory(secret.data(), secret.size());
    throw std::runtime_error("Credential input size/content is invalid.");
  }
  return secret;
}

std::filesystem::path CredentialPath(const std::filesystem::path& root,
                                     const wchar_t* name) {
  return root / (std::wstring(name) + L".dpapi");
}

bool CredentialPresent(const std::filesystem::path& root,
                       const wchar_t* name) {
  const auto path = CredentialPath(root, name);
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = GetLastError();
    if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
      return false;
    }
    throw std::runtime_error("Credential presence check failed.");
  }
  if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    throw std::runtime_error("Credential file cannot be a reparse point.");
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    throw std::runtime_error("Credential path unexpectedly resolves to a directory.");
  }
  return true;
}

void StoreSecret(const std::filesystem::path& root, const wchar_t* name) {
  GuardProductionPath(root);
  std::string secret = ReadSecretFromRedirectedStdin();
  try {
    quantara::CredentialVault(root).Store(name, secret);
  } catch (...) {
    SecureZeroMemory(secret.data(), secret.size());
    throw;
  }
  SecureZeroMemory(secret.data(), secret.size());
  GuardProductionPath(root);
  RejectReparsePointIfPresent(CredentialPath(root, name));
}

void RemoveAll(const std::filesystem::path& root) {
  GuardProductionPath(root);
  quantara::CredentialVault vault(root);
  vault.Remove(kApiKeyName);
  vault.Remove(kApiSecretName);
}

void PrintStatus(const std::filesystem::path& root) {
  GuardProductionPath(root);
  const bool api_key_present = CredentialPresent(root, kApiKeyName);
  const bool api_secret_present = CredentialPresent(root, kApiSecretName);
  std::cout << "{\"apiKeyPresent\":"
            << (api_key_present ? "true" : "false")
            << ",\"apiSecretPresent\":"
            << (api_secret_present ? "true" : "false") << "}\n";
}

bool RunSelfTest() noexcept {
  std::filesystem::path root;
  std::error_code cleanup_error;
  try {
    if (ParseCommand(L"--store-api-key") != Command::kStoreApiKey ||
        ParseCommand(L"--store-api-secret") != Command::kStoreApiSecret ||
        ParseCommand(L"--remove-all") != Command::kRemoveAll ||
        ParseCommand(L"--status") != Command::kStatus ||
        ParseCommand(L"--unknown").has_value()) {
      std::cerr << "Credential provisioner command parser self-test failed.\n";
      return false;
    }

    root = std::filesystem::temp_directory_path() /
           (L"quantara-credential-provisioner-self-test-" +
            std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(root, cleanup_error);

    quantara::CredentialVault vault(root);
    vault.Store(kApiKeyName, "self-test-key");
    vault.Store(kApiSecretName, "self-test-secret");
    if (!CredentialPresent(root, kApiKeyName) ||
        !CredentialPresent(root, kApiSecretName)) {
      std::cerr << "Credential provisioner presence self-test failed.\n";
      std::filesystem::remove_all(root, cleanup_error);
      return false;
    }

    const auto key = vault.Load(kApiKeyName);
    const auto secret = vault.Load(kApiSecretName);
    if (!key.has_value() || *key != "self-test-key" || !secret.has_value() ||
        *secret != "self-test-secret") {
      std::cerr << "Credential provisioner DPAPI round-trip self-test failed.\n";
      std::filesystem::remove_all(root, cleanup_error);
      return false;
    }

    vault.Remove(kApiKeyName);
    vault.Remove(kApiSecretName);
    const bool removed = !CredentialPresent(root, kApiKeyName) &&
                         !CredentialPresent(root, kApiSecretName);
    std::filesystem::remove_all(root, cleanup_error);
    if (!removed) {
      std::cerr << "Credential provisioner removal self-test failed.\n";
    }
    return removed;
  } catch (const std::exception& error) {
    std::cerr << "Credential provisioner self-test exception: " << error.what()
              << "\n";
    if (!root.empty()) {
      std::filesystem::remove_all(root, cleanup_error);
    }
    return false;
  } catch (...) {
    std::cerr << "Credential provisioner self-test failed with an unknown exception.\n";
    if (!root.empty()) {
      std::filesystem::remove_all(root, cleanup_error);
    }
    return false;
  }
}

void PrintUsage() {
  std::cerr
      << "Usage: quantara_windows_credentials --store-api-key|--store-api-secret|--remove-all|--status\n"
      << "Secrets are accepted only through redirected standard input and are never accepted as command-line arguments.\n";
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc != 2) {
    PrintUsage();
    return 2;
  }

  const auto command = ParseCommand(argv[1]);
  if (!command.has_value()) {
    PrintUsage();
    return 2;
  }
  if (*command == Command::kSelfTest) {
    if (!RunSelfTest()) {
      std::cerr << "Windows credential provisioner self-test failed.\n";
      return 1;
    }
    std::cout << "Windows credential provisioner self-test passed.\n";
    return 0;
  }

  if (!IsElevatedAdministrator()) {
    std::cerr << "Credential provisioning requires an elevated local administrator.\n";
    return 3;
  }

  try {
    const auto root = ProgramDataCredentialRoot();
    switch (*command) {
      case Command::kStoreApiKey:
        StoreSecret(root, kApiKeyName);
        std::cout << "Bitunix API key stored in Windows-protected service storage.\n";
        return 0;
      case Command::kStoreApiSecret:
        StoreSecret(root, kApiSecretName);
        std::cout << "Bitunix API secret stored in Windows-protected service storage.\n";
        return 0;
      case Command::kRemoveAll:
        RemoveAll(root);
        std::cout << "Quantara Windows service credentials removed.\n";
        return 0;
      case Command::kStatus:
        PrintStatus(root);
        return 0;
      case Command::kSelfTest:
        return 1;
    }
  } catch (const std::exception& error) {
    std::cerr << "Credential operation failed: " << error.what() << "\n";
    return 4;
  }

  return 4;
}
