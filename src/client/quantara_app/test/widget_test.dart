import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the real market data safety boundary', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('داده بازار واقعی'), findsOneWidget);
    expect(find.textContaining('بازار عمومی Bitunix'), findsOneWidget);
    expect(find.textContaining('بدون سفارش واقعی'), findsOneWidget);
    expect(find.text('رادار موقعیت‌ها'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens analysis with chart, timeframes, and risk plan', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('تحلیل'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Lightweight Charts'), findsOneWidget);
    expect(find.text('هم‌سویی چندتایم‌فریمی'), findsOneWidget);
    expect(find.text('پیشنهاد مدیریت سرمایه'), findsOneWidget);
    expect(find.text('حمایت و مقاومت روی نمودار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds a verified symbol to the watchlist', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('واچ‌لیست'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'XRP');
    await tester.tap(find.text('بررسی و افزودن'));
    await tester.pumpAndSettle();

    expect(find.text('XRPUSDT'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens profile with settings and honest connection states', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('پروفایل'));
    await tester.pumpAndSettle();

    expect(find.text('Bitunix Futures'), findsOneWidget);
    expect(find.text('پروفایل و تنظیمات'), findsOneWidget);
    expect(find.text('زبان'), findsOneWidget);
    expect(find.text('حساب خصوصی و اجرای سفارش'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches Persian RTL to English LTR without losing state', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final preferences = MemoryAppPreferencesStore();
    await tester.pumpWidget(_testApp(preferencesStore: preferences));
    await tester.pumpAndSettle();

    await tester.tap(find.text('پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انگلیسی'));
    await tester.pumpAndSettle();

    expect(find.text('Profile & settings'), findsOneWidget);
    expect(find.text('Radar'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Profile & settings'))),
      TextDirection.ltr,
    );
    expect(preferences.value?.languageCode, 'en');

    await tester.tap(find.text('Radar').last);
    await tester.pumpAndSettle();
    expect(find.text('BTCUSDT'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme toggles and deep scrolling stay stable', (tester) async {
    _setViewport(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.25;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('حالت روشن'));
    await tester.pump();
    await tester.tap(find.text('تحلیل'));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('uses side navigation on desktop', (tester) async {
    _setViewport(tester, const Size(1440, 1000));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('all destinations survive small width and large text', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    for (final target in {
      Icons.view_list_outlined: 'واچ‌لیست',
      Icons.candlestick_chart_outlined: 'تحلیل',
      Icons.person_outline_rounded: 'پروفایل',
      Icons.radar_outlined: 'رادار',
    }.entries) {
      await tester.tap(find.byIcon(target.key));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow on ${target.value}',
      );
    }
  });

  testWidgets('profile remains available when market loading fails', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      QuantaraApp(
        repository: const _FailingRepository(),
        settingsStore: MemoryOwnerAlphaSettingsStore(),
        preferencesStore: MemoryAppPreferencesStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('پروفایل'));
    await tester.pumpAndSettle();

    expect(find.text('پروفایل و تنظیمات'), findsOneWidget);
    expect(find.text('Bitunix Futures'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp({MemoryAppPreferencesStore? preferencesStore}) {
  return QuantaraApp(
    repository: const FakeOwnerAlphaRepository(),
    settingsStore: MemoryOwnerAlphaSettingsStore(),
    preferencesStore: preferencesStore,
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final class _FailingRepository implements OwnerAlphaRepository {
  const _FailingRepository();

  @override
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  }) {
    throw StateError('offline');
  }
}
