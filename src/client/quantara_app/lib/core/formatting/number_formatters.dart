abstract final class QuantaraNumberFormat {
  static const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  static String marketValue(double value, {String? unit}) {
    final decimals = switch (value.abs()) {
      >= 10000 => 0,
      >= 1 => 2,
      _ => 4,
    };
    final formatted = _groupLatin(value, decimals);
    return unit == null ? formatted : '$formatted $unit';
  }

  static String marketPercent(double value, {int decimals = 2}) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(decimals)}%';
  }

  static String persianInteger(int value) => _toPersian(value.toString());

  static String persianDecimal(double value, {int decimals = 1}) {
    final latin = value.toStringAsFixed(decimals).replaceAll('.', '٫');
    return _toPersian(latin);
  }

  static String persianPercent(double value, {int decimals = 0}) {
    return '${persianDecimal(value, decimals: decimals)}٪';
  }

  static String relativePersian(Duration age) {
    final safeAge = age.isNegative ? Duration.zero : age;
    if (safeAge.inSeconds < 60) {
      return '${persianInteger(safeAge.inSeconds)} ثانیه پیش';
    }
    if (safeAge.inMinutes < 60) {
      return '${persianInteger(safeAge.inMinutes)} دقیقه پیش';
    }
    return '${persianInteger(safeAge.inHours)} ساعت پیش';
  }

  static String _groupLatin(double value, int decimals) {
    final parts = value.toStringAsFixed(decimals).split('.');
    final integer = parts.first;
    final negative = integer.startsWith('-');
    final digits = negative ? integer.substring(1) : integer;
    final buffer = StringBuffer();

    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }

    final sign = negative ? '-' : '';
    final fraction = parts.length == 2 ? '.${parts[1]}' : '';
    return '$sign$buffer$fraction';
  }

  static String _toPersian(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final digit = int.tryParse(char);
      buffer.write(digit == null ? char : _persianDigits[digit]);
    }
    return buffer.toString();
  }
}
