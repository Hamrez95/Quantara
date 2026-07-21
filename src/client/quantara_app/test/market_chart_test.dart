import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/cockpit/data/mock_cockpit_repository.dart';
import 'package:quantara_app/features/market_analysis/data/demo_market_chart_factory.dart';
import 'package:quantara_app/features/market_analysis/presentation/quantara_candlestick_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('same symbol and timeframe produce identical chart analysis', () {
    final quote = MockCockpitRepository.demoSnapshot.watchlist.first;

    final first = DemoMarketChartFactory.create(quote: quote, timeframe: '1h');
    final second = DemoMarketChartFactory.create(quote: quote, timeframe: '1h');

    expect(first.fingerprint, second.fingerprint);
    expect(first.candles.length, 90);
    expect(first.latestCandle.close, closeTo(quote.price, 0.000001));
    expect(first.zones, isNotEmpty);
  });

  test('different timeframes produce different candle structures', () {
    final quote = MockCockpitRepository.demoSnapshot.watchlist.first;

    final fifteenMinutes = DemoMarketChartFactory.create(
      quote: quote,
      timeframe: '15m',
    );
    final fourHours = DemoMarketChartFactory.create(
      quote: quote,
      timeframe: '4h',
    );

    expect(fifteenMinutes.fingerprint, isNot(fourHours.fingerprint));
    expect(
      fifteenMinutes.candles[1].openTime.difference(
        fifteenMinutes.candles.first.openTime,
      ),
      const Duration(minutes: 15),
    );
    expect(
      fourHours.candles[1].openTime.difference(
        fourHours.candles.first.openTime,
      ),
      const Duration(hours: 4),
    );
    expect(
      fourHours.zones.every(
        (zone) =>
            zone.lower > 0 &&
            zone.upper >= zone.lower &&
            zone.strength >= 0 &&
            zone.strength <= 1,
      ),
      isTrue,
    );
  });

  testWidgets('timeframe selection replaces the rendered candle analysis', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('بازار'));
    await tester.pump();
    final chartFinder = find.byType(QuantaraCandlestickChart);
    expect(chartFinder, findsOneWidget);
    final oneHour = tester.widget<QuantaraCandlestickChart>(chartFinder);

    await tester.tap(find.byKey(const ValueKey('timeframe-4h')));
    await tester.pump();
    final fourHours = tester.widget<QuantaraCandlestickChart>(chartFinder);

    expect(oneHour.analysis.timeframe, '1h');
    expect(fourHours.analysis.timeframe, '4h');
    expect(oneHour.analysis.fingerprint, isNot(fourHours.analysis.fingerprint));
    expect(find.text('حمایت و مقاومت'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('candlestick view survives theme changes and large text', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('بازار'));
    await tester.pump();

    for (var attempt = 0; attempt < 4; attempt++) {
      final tooltip = attempt.isEven ? 'حالت روشن' : 'حالت تیره';
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.byType(QuantaraCandlestickChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
