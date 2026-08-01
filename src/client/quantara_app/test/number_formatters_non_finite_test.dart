import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/formatting/number_formatters.dart';

void main() {
  test('market value renders a bounded placeholder for non-finite values', () {
    expect(QuantaraNumberFormat.marketValue(double.nan), '—');
    expect(
      QuantaraNumberFormat.marketValue(double.infinity, unit: 'USDT'),
      '— USDT',
    );
    expect(QuantaraNumberFormat.marketValue(double.negativeInfinity), '—');
  });

  test('percent and Persian formatting do not throw on non-finite values', () {
    expect(QuantaraNumberFormat.marketPercent(double.nan), '—');
    expect(QuantaraNumberFormat.persianDecimal(double.infinity), '—');
    expect(QuantaraNumberFormat.persianPercent(double.negativeInfinity), '—');
  });

  test('finite formatting remains unchanged', () {
    expect(
      QuantaraNumberFormat.marketValue(1234.5, unit: 'USDT'),
      '1,234.50 USDT',
    );
    expect(QuantaraNumberFormat.marketPercent(1.25), '+1.25%');
  });
}
