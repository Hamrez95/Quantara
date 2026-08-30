#pragma once

#include <charconv>
#include <cctype>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace quantara {

struct BitunixPendingTpSlOrder final {
  std::string order_id;
  std::string position_id;
  std::string symbol;
  std::string take_profit_price;
  std::string stop_loss_price;
  std::string take_profit_quantity;
  std::string stop_loss_quantity;
};

namespace bitunix_pending_tpsl_detail {

constexpr std::size_t kMaxBodyBytes = 4 * 1024 * 1024;
constexpr std::size_t kMaxOrders = 100;
constexpr std::size_t kMaxStringBytes = 512;
constexpr int kMaxDepth = 32;

class JsonReader final {
 public:
  explicit JsonReader(std::string_view input) noexcept : input_(input) {}

  bool AtEnd() noexcept {
    SkipWhitespace();
    return offset_ == input_.size();
  }

  bool Consume(char expected) noexcept {
    SkipWhitespace();
    if (offset_ >= input_.size() || input_[offset_] != expected) return false;
    ++offset_;
    return true;
  }

  std::optional<std::string> String() noexcept {
    SkipWhitespace();
    if (offset_ >= input_.size() || input_[offset_] != '"') return std::nullopt;
    ++offset_;
    std::string result;
    try {
      while (offset_ < input_.size()) {
        const unsigned char c = static_cast<unsigned char>(input_[offset_++]);
        if (c == '"') return result;
        if (c < 0x20) return std::nullopt;
        if (c != '\\') {
          if (result.size() >= kMaxStringBytes) return std::nullopt;
          result.push_back(static_cast<char>(c));
          continue;
        }
        if (offset_ >= input_.size()) return std::nullopt;
        const char escape = input_[offset_++];
        char decoded = 0;
        switch (escape) {
          case '"': decoded = '"'; break;
          case '\\': decoded = '\\'; break;
          case '/': decoded = '/'; break;
          case 'b': decoded = '\b'; break;
          case 'f': decoded = '\f'; break;
          case 'n': decoded = '\n'; break;
          case 'r': decoded = '\r'; break;
          case 't': decoded = '\t'; break;
          case 'u': return std::nullopt;
          default: return std::nullopt;
        }
        if (result.size() >= kMaxStringBytes) return std::nullopt;
        result.push_back(decoded);
      }
    } catch (...) {
      return std::nullopt;
    }
    return std::nullopt;
  }

  std::optional<std::int64_t> Integer() noexcept {
    SkipWhitespace();
    const auto start = offset_;
    if (offset_ < input_.size() && input_[offset_] == '-') ++offset_;
    const auto digits = offset_;
    while (offset_ < input_.size() &&
           std::isdigit(static_cast<unsigned char>(input_[offset_])) != 0) {
      ++offset_;
    }
    if (digits == offset_) {
      offset_ = start;
      return std::nullopt;
    }
    if (offset_ < input_.size() &&
        (input_[offset_] == '.' || input_[offset_] == 'e' || input_[offset_] == 'E')) {
      offset_ = start;
      return std::nullopt;
    }
    std::int64_t value = 0;
    const auto parsed =
        std::from_chars(input_.data() + start, input_.data() + offset_, value);
    if (parsed.ec != std::errc{} || parsed.ptr != input_.data() + offset_) {
      offset_ = start;
      return std::nullopt;
    }
    return value;
  }

  bool SkipValue(int depth = 0) noexcept {
    if (depth > kMaxDepth) return false;
    SkipWhitespace();
    if (offset_ >= input_.size()) return false;
    if (input_[offset_] == '"') return String().has_value();
    if (input_[offset_] == '{') {
      ++offset_;
      SkipWhitespace();
      if (Consume('}')) return true;
      while (true) {
        if (!String().has_value() || !Consume(':') || !SkipValue(depth + 1)) return false;
        if (Consume('}')) return true;
        if (!Consume(',')) return false;
      }
    }
    if (input_[offset_] == '[') {
      ++offset_;
      SkipWhitespace();
      if (Consume(']')) return true;
      while (true) {
        if (!SkipValue(depth + 1)) return false;
        if (Consume(']')) return true;
        if (!Consume(',')) return false;
      }
    }
    if (input_.substr(offset_, 4) == "true") {
      offset_ += 4;
      return true;
    }
    if (input_.substr(offset_, 5) == "false") {
      offset_ += 5;
      return true;
    }
    if (input_.substr(offset_, 4) == "null") {
      offset_ += 4;
      return true;
    }
    return SkipNumber();
  }

 private:
  void SkipWhitespace() noexcept {
    while (offset_ < input_.size() &&
           std::isspace(static_cast<unsigned char>(input_[offset_])) != 0) {
      ++offset_;
    }
  }

  bool SkipNumber() noexcept {
    const auto start = offset_;
    if (offset_ < input_.size() && input_[offset_] == '-') ++offset_;
    if (offset_ >= input_.size()) return false;
    if (input_[offset_] == '0') {
      ++offset_;
    } else {
      if (std::isdigit(static_cast<unsigned char>(input_[offset_])) == 0) {
        offset_ = start;
        return false;
      }
      while (offset_ < input_.size() &&
             std::isdigit(static_cast<unsigned char>(input_[offset_])) != 0) {
        ++offset_;
      }
    }
    if (offset_ < input_.size() && input_[offset_] == '.') {
      ++offset_;
      const auto fraction_start = offset_;
      while (offset_ < input_.size() &&
             std::isdigit(static_cast<unsigned char>(input_[offset_])) != 0) {
        ++offset_;
      }
      if (fraction_start == offset_) {
        offset_ = start;
        return false;
      }
    }
    if (offset_ < input_.size() &&
        (input_[offset_] == 'e' || input_[offset_] == 'E')) {
      ++offset_;
      if (offset_ < input_.size() &&
          (input_[offset_] == '+' || input_[offset_] == '-')) {
        ++offset_;
      }
      const auto exponent_start = offset_;
      while (offset_ < input_.size() &&
             std::isdigit(static_cast<unsigned char>(input_[offset_])) != 0) {
        ++offset_;
      }
      if (exponent_start == offset_) {
        offset_ = start;
        return false;
      }
    }
    return offset_ > start;
  }

  std::string_view input_;
  std::size_t offset_ = 0;
};

inline bool IsAsciiToken(std::string_view value, std::size_t max_length,
                         bool allow_empty = false) noexcept {
  if ((!allow_empty && value.empty()) || value.size() > max_length) return false;
  for (const unsigned char c : value) {
    if (c < 0x21 || c > 0x7e || c == '"' || c == '\\') return false;
  }
  return true;
}

inline bool ReadToken(JsonReader& reader, std::string& target,
                      std::size_t max_length, bool allow_empty = false) noexcept {
  const auto value = reader.String();
  if (!value.has_value() || !IsAsciiToken(*value, max_length, allow_empty)) return false;
  target = *value;
  return true;
}

inline bool ParseOrder(JsonReader& reader, BitunixPendingTpSlOrder& out) noexcept {
  if (!reader.Consume('{')) return false;
  bool has_id = false;
  bool has_position_id = false;
  bool has_symbol = false;
  bool has_tp_price = false;
  bool has_sl_price = false;
  bool has_tp_qty = false;
  bool has_sl_qty = false;
  if (reader.Consume('}')) return false;

  while (true) {
    const auto key = reader.String();
    if (!key.has_value() || !reader.Consume(':')) return false;
    if (*key == "id") {
      if (has_id || !ReadToken(reader, out.order_id, 128)) return false;
      has_id = true;
    } else if (*key == "positionId") {
      if (has_position_id || !ReadToken(reader, out.position_id, 128)) return false;
      has_position_id = true;
    } else if (*key == "symbol") {
      if (has_symbol || !ReadToken(reader, out.symbol, 32)) return false;
      has_symbol = true;
    } else if (*key == "tpPrice") {
      if (has_tp_price || !ReadToken(reader, out.take_profit_price, 64, true)) return false;
      has_tp_price = true;
    } else if (*key == "slPrice") {
      if (has_sl_price || !ReadToken(reader, out.stop_loss_price, 64, true)) return false;
      has_sl_price = true;
    } else if (*key == "tpQty") {
      if (has_tp_qty || !ReadToken(reader, out.take_profit_quantity, 64, true)) return false;
      has_tp_qty = true;
    } else if (*key == "slQty") {
      if (has_sl_qty || !ReadToken(reader, out.stop_loss_quantity, 64, true)) return false;
      has_sl_qty = true;
    } else if (!reader.SkipValue()) {
      return false;
    }
    if (reader.Consume('}')) break;
    if (!reader.Consume(',')) return false;
  }

  if (!has_id || !has_position_id || !has_symbol) return false;
  const bool has_tp_leg = has_tp_price && has_tp_qty &&
                          !out.take_profit_price.empty() &&
                          !out.take_profit_quantity.empty();
  const bool has_sl_leg = has_sl_price && has_sl_qty &&
                          !out.stop_loss_price.empty() &&
                          !out.stop_loss_quantity.empty();
  return has_tp_leg || has_sl_leg;
}

inline bool ParseArray(JsonReader& reader,
                       std::vector<BitunixPendingTpSlOrder>& orders) noexcept {
  if (!reader.Consume('[')) return false;
  if (reader.Consume(']')) return true;
  while (true) {
    if (orders.size() >= kMaxOrders) return false;
    BitunixPendingTpSlOrder order;
    if (!ParseOrder(reader, order)) return false;
    orders.push_back(std::move(order));
    if (reader.Consume(']')) return true;
    if (!reader.Consume(',')) return false;
  }
}

}  // namespace bitunix_pending_tpsl_detail

// Parses only Bitunix's authenticated pending TP/SL endpoint response. The
// result preserves exchange-reported TP/SL quantities because management
// authority must never infer full protection from price presence alone.
[[nodiscard]] inline std::optional<std::vector<BitunixPendingTpSlOrder>>
ParseBitunixPendingTpSlOrdersResponse(std::string_view body) noexcept {
  using namespace bitunix_pending_tpsl_detail;
  try {
    if (body.empty() || body.size() > kMaxBodyBytes) return std::nullopt;
    JsonReader reader(body);
    if (!reader.Consume('{')) return std::nullopt;
    bool has_code = false;
    bool has_data = false;
    std::vector<BitunixPendingTpSlOrder> orders;
    if (reader.Consume('}')) return std::nullopt;

    while (true) {
      const auto key = reader.String();
      if (!key.has_value() || !reader.Consume(':')) return std::nullopt;
      if (*key == "code") {
        if (has_code) return std::nullopt;
        const auto code = reader.Integer();
        if (!code.has_value() || *code != 0) return std::nullopt;
        has_code = true;
      } else if (*key == "data") {
        if (has_data || !ParseArray(reader, orders)) return std::nullopt;
        has_data = true;
      } else if (!reader.SkipValue()) {
        return std::nullopt;
      }
      if (reader.Consume('}')) break;
      if (!reader.Consume(',')) return std::nullopt;
    }

    if (!has_code || !has_data || !reader.AtEnd()) return std::nullopt;
    return orders;
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
