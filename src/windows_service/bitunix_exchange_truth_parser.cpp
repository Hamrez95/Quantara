#include "bitunix_exchange_truth_parser.h"

#include <charconv>
#include <cctype>
#include <limits>
#include <utility>

namespace quantara {
namespace {

constexpr std::size_t kMaxBodyBytes = 4 * 1024 * 1024;
constexpr std::size_t kMaxPositions = 1024;
constexpr std::size_t kMaxOrders = 1024;
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
          case 'u':
            // Required reconciliation identifiers are ASCII. Escaped Unicode is
            // deliberately unsupported rather than decoded incorrectly.
            return std::nullopt;
          default:
            return std::nullopt;
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
    const auto parsed = std::from_chars(input_.data() + start, input_.data() + offset_, value);
    if (parsed.ec != std::errc{} || parsed.ptr != input_.data() + offset_) {
      offset_ = start;
      return std::nullopt;
    }
    return value;
  }

  std::optional<bool> Boolean() noexcept {
    SkipWhitespace();
    if (input_.substr(offset_, 4) == "true") {
      offset_ += 4;
      return true;
    }
    if (input_.substr(offset_, 5) == "false") {
      offset_ += 5;
      return false;
    }
    return std::nullopt;
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
             std::isdigit(static_cast<unsigned char>(input_[offset_])) != 0) ++offset_;
    }
    if (offset_ < input_.size() && input_[offset_] == '.') {
      ++offset_;
      const auto fraction_start = offset_;
      while (offset_ < input_.size() &&
             std::isdigit(static_cast<unsigned char>(input_[offset_])) != 0) ++offset_;
      if (fraction_start == offset_) {
        offset_ = start;
        return false;
      }
    }
    if (offset_ < input_.size() && (input_[offset_] == 'e' || input_[offset_] == 'E')) {
      ++offset_;
      if (offset_ < input_.size() && (input_[offset_] == '+' || input_[offset_] == '-')) ++offset_;
      const auto exponent_start = offset_;
      while (offset_ < input_.size() &&
             std::isdigit(static_cast<unsigned char>(input_[offset_])) != 0) ++offset_;
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

bool IsAsciiToken(std::string_view value, std::size_t max_length) noexcept {
  if (value.empty() || value.size() > max_length) return false;
  for (unsigned char c : value) {
    if (c < 0x21 || c > 0x7e || c == '"' || c == '\\') return false;
  }
  return true;
}

bool ParsePendingPosition(JsonReader& reader, BitunixPendingPosition& out) noexcept {
  if (!reader.Consume('{')) return false;
  bool has_position_id = false;
  bool has_symbol = false;
  bool has_quantity = false;
  bool has_side = false;
  bool has_margin_mode = false;
  bool has_position_mode = false;
  bool has_leverage = false;
  if (reader.Consume('}')) return false;
  while (true) {
    const auto key = reader.String();
    if (!key.has_value() || !reader.Consume(':')) return false;
    if (*key == "positionId") {
      if (has_position_id) return false;
      const auto value = reader.String();
      if (!value.has_value() || !IsAsciiToken(*value, 128)) return false;
      out.position_id = *value;
      has_position_id = true;
    } else if (*key == "symbol") {
      if (has_symbol) return false;
      const auto value = reader.String();
      if (!value.has_value() || !IsAsciiToken(*value, 32)) return false;
      out.symbol = *value;
      has_symbol = true;
    } else if (*key == "qty") {
      if (has_quantity) return false;
      const auto value = reader.String();
      if (!value.has_value() || !IsAsciiToken(*value, 64)) return false;
      out.quantity = *value;
      has_quantity = true;
    } else if (*key == "side") {
      if (has_side) return false;
      const auto value = reader.String();
      if (!value.has_value() || (*value != "LONG" && *value != "SHORT")) return false;
      out.side = *value;
      has_side = true;
    } else if (*key == "marginMode") {
      if (has_margin_mode) return false;
      const auto value = reader.String();
      if (!value.has_value() || (*value != "ISOLATION" && *value != "CROSS")) return false;
      out.margin_mode = *value;
      has_margin_mode = true;
    } else if (*key == "positionMode") {
      if (has_position_mode) return false;
      const auto value = reader.String();
      if (!value.has_value() || (*value != "ONE_WAY" && *value != "HEDGE")) return false;
      out.position_mode = *value;
      has_position_mode = true;
    } else if (*key == "leverage") {
      if (has_leverage) return false;
      const auto value = reader.Integer();
      if (!value.has_value() || *value <= 0 || *value > 1000) return false;
      out.leverage = static_cast<int>(*value);
      has_leverage = true;
    } else if (!reader.SkipValue()) {
      return false;
    }
    if (reader.Consume('}')) break;
    if (!reader.Consume(',')) return false;
  }
  return has_position_id && has_symbol && has_quantity && has_side && has_margin_mode &&
         has_position_mode && has_leverage;
}

bool ParsePendingOrder(JsonReader& reader, BitunixPendingOrder& out) noexcept {
  if (!reader.Consume('{')) return false;
  bool has_order_id = false;
  bool has_symbol = false;
  bool has_status = false;
  bool has_reduce_only = false;
  if (reader.Consume('}')) return false;
  while (true) {
    const auto key = reader.String();
    if (!key.has_value() || !reader.Consume(':')) return false;
    auto read_optional_token = [&](std::string& target, std::size_t max_length) noexcept {
      const auto value = reader.String();
      if (!value.has_value() || !IsAsciiToken(*value, max_length)) return false;
      target = *value;
      return true;
    };
    if (*key == "orderId") {
      if (has_order_id || !read_optional_token(out.order_id, 128)) return false;
      has_order_id = true;
    } else if (*key == "clientId") {
      if (!out.client_id.empty() || !read_optional_token(out.client_id, 128)) return false;
    } else if (*key == "positionId") {
      if (!out.position_id.empty() || !read_optional_token(out.position_id, 128)) return false;
    } else if (*key == "symbol") {
      if (has_symbol || !read_optional_token(out.symbol, 32)) return false;
      has_symbol = true;
    } else if (*key == "status") {
      if (has_status || !read_optional_token(out.status, 32)) return false;
      if (out.status != "NEW" && out.status != "PART_FILLED" && out.status != "INIT") return false;
      has_status = true;
    } else if (*key == "reduceOnly") {
      if (has_reduce_only) return false;
      const auto value = reader.Boolean();
      if (!value.has_value()) return false;
      out.reduce_only = *value;
      has_reduce_only = true;
    } else if (*key == "tpPrice") {
      if (!out.take_profit_price.empty() || !read_optional_token(out.take_profit_price, 64)) return false;
    } else if (*key == "slPrice") {
      if (!out.stop_loss_price.empty() || !read_optional_token(out.stop_loss_price, 64)) return false;
    } else if (!reader.SkipValue()) {
      return false;
    }
    if (reader.Consume('}')) break;
    if (!reader.Consume(',')) return false;
  }
  return has_order_id && has_symbol && has_status && has_reduce_only;
}

bool ParsePositionArray(JsonReader& reader,
                        std::vector<BitunixPendingPosition>& positions) noexcept {
  if (!reader.Consume('[')) return false;
  if (reader.Consume(']')) return true;
  while (true) {
    if (positions.size() >= kMaxPositions) return false;
    BitunixPendingPosition position;
    if (!ParsePendingPosition(reader, position)) return false;
    positions.push_back(std::move(position));
    if (reader.Consume(']')) return true;
    if (!reader.Consume(',')) return false;
  }
}

bool ParseOrderArray(JsonReader& reader, std::vector<BitunixPendingOrder>& orders) noexcept {
  if (!reader.Consume('[')) return false;
  if (reader.Consume(']')) return true;
  while (true) {
    if (orders.size() >= kMaxOrders) return false;
    BitunixPendingOrder order;
    if (!ParsePendingOrder(reader, order)) return false;
    orders.push_back(std::move(order));
    if (reader.Consume(']')) return true;
    if (!reader.Consume(',')) return false;
  }
}

bool ParseOrderData(JsonReader& reader, BitunixPendingOrdersSnapshot& snapshot) noexcept {
  if (!reader.Consume('{')) return false;
  bool has_list = false;
  bool has_total = false;
  if (reader.Consume('}')) return false;
  while (true) {
    const auto key = reader.String();
    if (!key.has_value() || !reader.Consume(':')) return false;
    if (*key == "orderList") {
      if (has_list || !ParseOrderArray(reader, snapshot.orders)) return false;
      has_list = true;
    } else if (*key == "total") {
      if (has_total) return false;
      const auto total = reader.Integer();
      if (!total.has_value() || *total < 0 || *total > 1000000) return false;
      snapshot.total = *total;
      has_total = true;
    } else if (!reader.SkipValue()) {
      return false;
    }
    if (reader.Consume('}')) break;
    if (!reader.Consume(',')) return false;
  }
  return has_list && has_total && snapshot.total >= static_cast<std::int64_t>(snapshot.orders.size());
}

template <typename DataParser>
bool ParseEnvelope(std::string_view body, DataParser&& parse_data) noexcept {
  if (body.empty() || body.size() > kMaxBodyBytes) return false;
  JsonReader reader(body);
  if (!reader.Consume('{')) return false;
  bool has_code = false;
  bool has_data = false;
  if (reader.Consume('}')) return false;
  while (true) {
    const auto key = reader.String();
    if (!key.has_value() || !reader.Consume(':')) return false;
    if (*key == "code") {
      if (has_code) return false;
      const auto code = reader.Integer();
      if (!code.has_value() || *code != 0) return false;
      has_code = true;
    } else if (*key == "data") {
      if (has_data || !parse_data(reader)) return false;
      has_data = true;
    } else if (!reader.SkipValue()) {
      return false;
    }
    if (reader.Consume('}')) break;
    if (!reader.Consume(',')) return false;
  }
  return has_code && has_data && reader.AtEnd();
}

}  // namespace

std::optional<std::vector<BitunixPendingPosition>>
ParseBitunixPendingPositionsResponse(std::string_view body) noexcept {
  try {
    std::vector<BitunixPendingPosition> positions;
    if (!ParseEnvelope(body, [&](JsonReader& reader) noexcept {
          return ParsePositionArray(reader, positions);
        })) {
      return std::nullopt;
    }
    return positions;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<BitunixPendingOrdersSnapshot>
ParseBitunixPendingOrdersResponse(std::string_view body) noexcept {
  try {
    BitunixPendingOrdersSnapshot snapshot;
    if (!ParseEnvelope(body, [&](JsonReader& reader) noexcept {
          return ParseOrderData(reader, snapshot);
        })) {
      return std::nullopt;
    }
    return snapshot;
  } catch (...) {
    return std::nullopt;
  }
}

}  // namespace quantara
