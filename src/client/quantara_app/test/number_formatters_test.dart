import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/formatting/number_formatters.dart';

void main() {
  test('keeps market prices in grouped Latin digits', () {
    expect(QuantaraNumberFormat.marketValue(118420.5), '118,421');
    expect(QuantaraNumberFormat.marketValue(3712.8), '3,712.80');
    expect(QuantaraNumberFormat.marketPercent(1.82), '+1.82%');
  });

  test('uses Persian digits for prose-oriented values', () {
    expect(QuantaraNumberFormat.persianInteger(12), '۱۲');
    expect(QuantaraNumberFormat.persianPercent(0.64, decimals: 1), '۰٫۶٪');
    expect(
      QuantaraNumberFormat.relativePersian(const Duration(seconds: 18)),
      '۱۸ ثانیه پیش',
    );
  });
}
