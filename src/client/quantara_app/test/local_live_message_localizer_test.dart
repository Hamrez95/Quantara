import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/localization/local_live_message_localizer.dart';

void main() {
  test('parses and localizes the dynamic affordability failure', () {
    const raw =
        'Available margin is 0.2522 USDT. The smallest exchange/margin '
        'floor among the selected symbols is about 1.9085 USDT '
        '(ETHUSDT, including three TP quantities and the safety buffer). '
        'Shortfall: 1.6563 USDT. The actual risk and stop distance checks may '
        'require more capital.';

    final summary = LocalLiveMessageLocalizer.affordability(raw);
    expect(summary, isNotNull);
    expect(summary!.symbol, 'ETHUSDT');
    expect(summary.availableMargin, '0.2522');
    expect(summary.minimumMargin, '1.9085');
    expect(summary.shortfall, '1.6563');
    final localized = LocalLiveMessageLocalizer.localize(raw, persian: true);
    expect(localized, contains('موجودی قابل استفاده'));
    expect(localized, contains('ETHUSDT'));
    expect(localized, isNot(contains('Available margin is')));
  });

  test('keeps English when the app language is English', () {
    const raw = 'Local live trading is stopped.';
    expect(LocalLiveMessageLocalizer.localize(raw, persian: false), raw);
  });
}
