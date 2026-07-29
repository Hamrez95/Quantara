import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled Vazirmatn fonts stay declared and available', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    const assets = [
      'assets/fonts/Vazirmatn-Regular.ttf',
      'assets/fonts/Vazirmatn-SemiBold.ttf',
      'assets/fonts/Vazirmatn-Bold.ttf',
    ];

    for (final asset in assets) {
      expect(pubspec, contains(asset));
      expect(File(asset).existsSync(), isTrue, reason: '$asset is missing');
    }
  });

  test('analysis chart stays Flutter-rendered with a trade-plan overlay', () {
    final wrapper = File(
      'lib/features/market_analysis/presentation/'
      'tradingview_lightweight_chart.dart',
    ).readAsStringSync();
    final painter = File(
      'lib/features/market_analysis/presentation/'
      'quantara_candlestick_chart.dart',
    ).readAsStringSync();

    expect(wrapper, isNot(contains('AndroidView')));
    expect(wrapper, contains('ChartTradeOverlay'));
    expect(painter, contains('_paintTradeOverlay'));
    expect(painter, contains("'ENTRY'"));
    expect(painter, contains("'SL'"));
  });
}
