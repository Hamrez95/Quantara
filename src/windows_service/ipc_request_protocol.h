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
};

struct ReadOnlyRequest final {
  std::string request_id;
  ReadOnlyRequestKind kind;
};

std::optional<ReadOnlyRequest> DecodeCanonicalReadOnlyRequest(
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
