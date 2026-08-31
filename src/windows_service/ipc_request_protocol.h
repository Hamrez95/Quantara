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
  kTightenExistingStop,
};

struct ManagementOnlyRequest final {
  std::string request_id;
  ManagementOnlyRequestKind kind;
  std::string position_id;
  double new_stop_price = 0.0;
};

std::optional<ReadOnlyRequest> DecodeCanonicalReadOnlyRequest(
    std::span<const std::uint8_t> frame) noexcept;

// Decodes the deliberately narrow mutation surface exposed by the Windows
// service. It can represent only a full close or a tighter stop request for one
// already-verified existing position. The stop trigger semantic is deliberately
// absent: production must preserve it from fresh exchange truth rather than let
// an IPC caller select or guess it. Generic orders, entries, leverage/margin
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
