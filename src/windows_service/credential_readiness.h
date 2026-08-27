#pragma once

#include <filesystem>

namespace quantara {

enum class CredentialReadiness {
  kMissing,
  kReady,
  kIncomplete,
  kInvalid,
};

CredentialReadiness EvaluateCredentialReadiness(
    const std::filesystem::path& root) noexcept;

}  // namespace quantara
