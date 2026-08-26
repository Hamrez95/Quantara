#include "credential_vault.h"

#include <Windows.h>
#include <dpapi.h>

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
  const auto temporary = path.wstring() + L".tmp";
  try {
    std::ofstream stream(std::filesystem::path(temporary), std::ios::binary | std::ios::trunc);
    if (!stream) {
      throw std::runtime_error("Credential vault temporary file could not be opened.");
    }
    stream.write(reinterpret_cast<const char*>(output.pbData), output.cbData);
    stream.close();
    if (!stream) {
      throw std::runtime_error("Credential vault write failed.");
    }

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
