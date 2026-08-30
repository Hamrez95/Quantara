#include "ipc_request_protocol.h"

#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <string_view>

namespace quantara {
namespace {

constexpr std::string_view kPrefix =
    "{\"protocolVersion\":1,\"requestId\":\"";
constexpr std::string_view kHandshakeSuffix =
    "\",\"kind\":\"handshake\",\"payload\":{}}";
constexpr std::string_view kStatusSuffix =
    "\",\"kind\":\"statusRequest\",\"payload\":{}}";
constexpr std::string_view kCredentialReadinessSuffix =
    "\",\"kind\":\"credentialReadinessRequest\",\"payload\":{}}";
constexpr std::string_view kCloseExistingMiddle =
    "\",\"kind\":\"closeExistingPosition\",\"payload\":{\"positionId\":\"";
constexpr std::string_view kCloseExistingSuffix = "\"}}";

bool IsSafeRequestId(std::string_view value) noexcept {
  if (value.empty() || value.size() > 64) {
    return false;
  }
  for (const char ch : value) {
    const bool safe = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                      (ch >= '0' && ch <= '9') || ch == '.' || ch == '_' ||
                      ch == '-';
    if (!safe) {
      return false;
    }
  }
  return true;
}

bool IsSafePositionId(std::string_view value) noexcept {
  return !value.empty() && value.size() <= 64 &&
         std::all_of(value.begin(), value.end(), [](const char ch) {
           return std::isdigit(static_cast<unsigned char>(ch)) != 0;
         });
}

std::optional<ReadOnlyRequest> DecodeWithSuffix(std::string_view text,
                                                std::string_view suffix,
                                                ReadOnlyRequestKind kind) {
  if (!text.starts_with(kPrefix) || !text.ends_with(suffix) ||
      text.size() <= kPrefix.size() + suffix.size()) {
    return std::nullopt;
  }
  const auto request_id = text.substr(
      kPrefix.size(), text.size() - kPrefix.size() - suffix.size());
  if (!IsSafeRequestId(request_id)) {
    return std::nullopt;
  }
  return ReadOnlyRequest{std::string(request_id), kind};
}

}  // namespace

std::optional<ReadOnlyRequest> DecodeCanonicalReadOnlyRequest(
    std::span<const std::uint8_t> frame) noexcept {
  try {
    if (frame.empty() || frame.size() > kWindowsServiceMaxFrameBytes) {
      return std::nullopt;
    }
    const std::string_view text(reinterpret_cast<const char*>(frame.data()),
                                frame.size());
    if (const auto handshake =
            DecodeWithSuffix(text, kHandshakeSuffix,
                             ReadOnlyRequestKind::kHandshake)) {
      return handshake;
    }
    if (const auto status =
            DecodeWithSuffix(text, kStatusSuffix,
                             ReadOnlyRequestKind::kStatusRequest)) {
      return status;
    }
    return DecodeWithSuffix(text, kCredentialReadinessSuffix,
                            ReadOnlyRequestKind::kCredentialReadinessRequest);
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<ManagementOnlyRequest> DecodeCanonicalManagementOnlyRequest(
    std::span<const std::uint8_t> frame) noexcept {
  try {
    if (frame.empty() || frame.size() > kWindowsServiceMaxFrameBytes) {
      return std::nullopt;
    }
    const std::string_view text(reinterpret_cast<const char*>(frame.data()),
                                frame.size());
    if (!text.starts_with(kPrefix) || !text.ends_with(kCloseExistingSuffix)) {
      return std::nullopt;
    }

    const auto middle_pos = text.find(kCloseExistingMiddle, kPrefix.size());
    if (middle_pos == std::string_view::npos || middle_pos == kPrefix.size()) {
      return std::nullopt;
    }
    const auto request_id = text.substr(kPrefix.size(), middle_pos - kPrefix.size());
    if (!IsSafeRequestId(request_id)) {
      return std::nullopt;
    }

    const auto position_begin = middle_pos + kCloseExistingMiddle.size();
    if (position_begin >= text.size() - kCloseExistingSuffix.size()) {
      return std::nullopt;
    }
    const auto position_id = text.substr(
        position_begin,
        text.size() - position_begin - kCloseExistingSuffix.size());
    if (!IsSafePositionId(position_id)) {
      return std::nullopt;
    }

    return ManagementOnlyRequest{
        std::string(request_id), ManagementOnlyRequestKind::kCloseExistingPosition,
        std::string(position_id)};
  } catch (...) {
    return std::nullopt;
  }
}

RequestReplayGuard::RequestReplayGuard(std::size_t capacity)
    : capacity_(capacity) {
  if (capacity_ == 0 || capacity_ > 4096) {
    throw std::invalid_argument("Replay guard capacity must be 1..4096.");
  }
}

bool RequestReplayGuard::Accept(const std::string& request_id) {
  if (seen_.contains(request_id)) {
    return false;
  }
  seen_.insert(request_id);
  order_.push_back(request_id);
  while (order_.size() > capacity_) {
    seen_.erase(order_.front());
    order_.pop_front();
  }
  return true;
}

}  // namespace quantara
