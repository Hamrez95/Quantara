#include "recovery_evidence_vault.h"

#include "credential_vault.h"

#include <charconv>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <unordered_set>
#include <utility>

namespace quantara {
namespace {

constexpr wchar_t kVaultName[] = L"management-recovery-evidence-v1";
constexpr std::string_view kHeader = "QRE1\n";
constexpr std::size_t kMaxRecords = 32;
constexpr std::size_t kMaxIdentityLength = 128;

bool IsSafeIdentity(std::string_view value) noexcept {
  if (value.empty() || value.size() > kMaxIdentityLength) return false;
  for (const unsigned char c : value) {
    const bool safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                      (c >= '0' && c <= '9') || c == '-' || c == '_' ||
                      c == ':' || c == '.';
    if (!safe) return false;
  }
  return true;
}

bool IsPersistable(const DurableReconciliationEvidence& item) noexcept {
  return IsSafeIdentity(item.position_id) && IsSafeIdentity(item.symbol) &&
         item.has_unambiguous_quantara_identity &&
         item.has_durable_reconstruction &&
         !item.has_conflicting_order_fill_or_history &&
         item.expected_take_profit_order_count >= 1 &&
         item.expected_take_profit_order_count <= 3;
}

std::string IdentityKey(const DurableReconciliationEvidence& item) {
  return item.position_id + "\n" + item.symbol;
}

std::string Serialize(
    const std::vector<DurableReconciliationEvidence>& evidence) {
  if (evidence.size() > kMaxRecords) {
    throw std::invalid_argument("Too many durable recovery evidence records.");
  }

  std::unordered_set<std::string> identities;
  std::string payload(kHeader);
  for (const auto& item : evidence) {
    if (!IsPersistable(item)) {
      throw std::invalid_argument("Durable recovery evidence is invalid.");
    }
    if (!identities.insert(IdentityKey(item)).second) {
      throw std::invalid_argument("Duplicate durable recovery evidence identity.");
    }

    payload.append(item.position_id);
    payload.push_back('\t');
    payload.append(item.symbol);
    payload.push_back('\t');
    payload.push_back(item.is_already_managed ? '1' : '0');
    payload.push_back('\t');
    payload.append(std::to_string(item.expected_take_profit_order_count));
    payload.push_back('\n');
  }
  return payload;
}

std::optional<std::size_t> ParseCount(std::string_view value) noexcept {
  if (value.empty() || value.size() > 2) return std::nullopt;
  std::size_t parsed = 0;
  const auto result =
      std::from_chars(value.data(), value.data() + value.size(), parsed);
  if (result.ec != std::errc{} || result.ptr != value.data() + value.size() ||
      parsed < 1 || parsed > 3) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<std::vector<DurableReconciliationEvidence>> Parse(
    std::string_view payload) noexcept {
  try {
    if (!payload.starts_with(kHeader)) return std::nullopt;
    payload.remove_prefix(kHeader.size());

    std::vector<DurableReconciliationEvidence> evidence;
    std::unordered_set<std::string> identities;
    while (!payload.empty()) {
      const auto newline = payload.find('\n');
      if (newline == std::string_view::npos) return std::nullopt;
      const auto line = payload.substr(0, newline);
      payload.remove_prefix(newline + 1);
      if (line.empty() || evidence.size() >= kMaxRecords) return std::nullopt;

      const auto first = line.find('\t');
      const auto second = first == std::string_view::npos
                              ? std::string_view::npos
                              : line.find('\t', first + 1);
      const auto third = second == std::string_view::npos
                             ? std::string_view::npos
                             : line.find('\t', second + 1);
      if (first == std::string_view::npos || second == std::string_view::npos ||
          third == std::string_view::npos ||
          line.find('\t', third + 1) != std::string_view::npos) {
        return std::nullopt;
      }

      const auto position_id = line.substr(0, first);
      const auto symbol = line.substr(first + 1, second - first - 1);
      const auto managed = line.substr(second + 1, third - second - 1);
      const auto target_count = line.substr(third + 1);
      const auto parsed_count = ParseCount(target_count);
      if (!IsSafeIdentity(position_id) || !IsSafeIdentity(symbol) ||
          (managed != "0" && managed != "1") || !parsed_count.has_value()) {
        return std::nullopt;
      }

      DurableReconciliationEvidence item{};
      item.position_id = std::string(position_id);
      item.symbol = std::string(symbol);
      item.has_unambiguous_quantara_identity = true;
      item.has_complete_exchange_stop = false;
      item.has_complete_exchange_take_profit_ladder = false;
      item.has_conflicting_order_fill_or_history = false;
      item.has_durable_reconstruction = true;
      item.is_already_managed = managed == "1";
      item.expected_take_profit_order_count = *parsed_count;
      if (!identities.insert(IdentityKey(item)).second) return std::nullopt;
      evidence.push_back(std::move(item));
    }
    return evidence;
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace

RecoveryEvidenceVault::RecoveryEvidenceVault(std::filesystem::path root)
    : root_(std::move(root)) {
  if (root_.empty()) {
    throw std::invalid_argument("Recovery evidence vault root is required.");
  }
}

void RecoveryEvidenceVault::Store(
    const std::vector<DurableReconciliationEvidence>& evidence) const {
  CredentialVault vault(root_);
  if (evidence.empty()) {
    vault.Remove(kVaultName);
    return;
  }
  vault.Store(kVaultName, Serialize(evidence));
}

std::optional<std::vector<DurableReconciliationEvidence>>
RecoveryEvidenceVault::Load() const noexcept {
  try {
    CredentialVault vault(root_);
    const auto payload = vault.Load(kVaultName);
    if (!payload.has_value()) {
      return std::vector<DurableReconciliationEvidence>{};
    }
    return Parse(*payload);
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
