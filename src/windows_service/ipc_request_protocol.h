#pragma once

#include <cstddef>
#include <cstdint>
#include <deque>
#include <optional>
#include <span>
#include <string>
#include <unordered_set>

namespace quantara {

constexpr std::size_t kWindowsServiceMaxFrameBytes = 64 * 1024;

enum class ReadOnlyRequestKind {
  kHandshake,
  kStatusRequest,
  kCredentialReadinessRequest,
};

struct ReadOnlyRequest final {
  std::string request_id;
  ReadOnlyRequestKind kind;
};

enum class ManagementOnlyRequestKind {
  kCloseExistingPosition,
};

struct ManagementOnlyRequest final {
  std::string request_id;
  ManagementOnlyRequestKind kind;
  std::string position_id;
};

std::optional<ReadOnlyRequest> DecodeCanonicalReadOnlyRequest(
    std::span<const std::uint8_t> frame) noexcept;

// Decodes the deliberately narrow mutation surface exposed by the Windows
// service. Only a full close of one already-verified existing position can be
// represented. Generic order payloads, entry instructions, leverage/margin
// changes and stop widening have no representation here.
std::optional<ManagementOnlyRequest> DecodeCanonicalManagementOnlyRequest(
    std::span<const std::uint8_t> frame) noexcept;

class RequestReplayGuard final {
 public:
  explicit RequestReplayGuard(std::size_t capacity = 256);

  bool Accept(const std::string& request_id);
  std::size_t size() const noexcept { return order_.size(); }

 private:
  std::size_t capacity_;
  std::deque<std::string> order_;
  std::unordered_set<std::string> seen_;
};

}  // namespace quantara
