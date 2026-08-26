#pragma once

#include <filesystem>
#include <optional>
#include <string>

namespace quantara {

class CredentialVault final {
 public:
  explicit CredentialVault(std::filesystem::path root);

  void Store(const std::wstring& name, const std::string& secret) const;
  std::optional<std::string> Load(const std::wstring& name) const;
  void Remove(const std::wstring& name) const;

 private:
  std::filesystem::path PathFor(const std::wstring& name) const;
  std::filesystem::path root_;
};

}  // namespace quantara
