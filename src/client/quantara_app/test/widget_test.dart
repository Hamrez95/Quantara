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

    final realData = find.textContaining('داده عمومی واقعی');
    for (
      var attempt = 0;
      attempt < 30 && realData.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(realData, findsOneWidget);
    expect(find.textContaining('کلید صرافی'), findsOneWidget);
    expect(find.textContaining('سفارش واقعی و برداشت'), findsOneWidget);
    expect(find.text('رادار موقعیت‌ها'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens analysis with chart, timeframes, and risk plan', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await _openDestination(tester, Icons.candlestick_chart_outlined);

    expect(find.textContaining('Lightweight Charts'), findsOneWidget);
    expect(find.text('هم‌سویی چندتایم‌فریمی'), findsOneWidget);
    expect(find.text('پیشنهاد مدیریت سرمایه'), findsOneWidget);
    expect(find.text('حمایت و مقاومت روی نمودار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('runs a symbol-specific paper strategy report', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await _openDestination(tester, Icons.candlestick_chart_outlined);
    await tester.tap(find.text('تست این تحلیل در آزمایشگاه'));
    await tester.pumpAndSettle();

    expect(find.text('آزمایشگاه'), findsWidgets);
    expect(find.text('BTCUSDT'), findsWidgets);
    expect(find.text('پیپر / تحقیق'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ساخت گزارش تاریخی'));
    await tester.pumpAndSettle();

    expect(find.text('کارنامه تست'), findsOneWidget);
    expect(find.text('وین‌ریت'), findsOneWidget);
    expect(find.text('SL'), findsOneWidget);
    expect(find.text('TP1 / TP2 / TP3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds a verified symbol to the watchlist', (tester) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await _openDestination(tester, Icons.view_list_outlined);
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

    await _openDestination(tester, Icons.person_outline_rounded);

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

    await _openDestination(tester, Icons.person_outline_rounded);
    await tester.tap(find.text('انگلیسی'));
    await tester.pumpAndSettle();

    expect(find.text('Profile & settings'), findsOneWidget);
    expect(find.text('Radar'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.text('Profile & settings'))),
      TextDirection.ltr,
    );
    expect(preferences.value?.languageCode, 'en');

    await _openDestination(tester, Icons.radar_outlined);
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
    await _openDestination(tester, Icons.candlestick_chart_outlined);
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
      await _openDestination(tester, target.key);
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
        opportunityStateStore: MemoryOpportunityStateStore(),
        notificationGateway: RecordingSetupNotificationGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await _openDestination(tester, Icons.person_outline_rounded);

    expect(find.text('پروفایل و تنظیمات'), findsOneWidget);
    expect(find.text('Bitunix Futures'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDestination(WidgetTester tester, IconData icon) async {
  final navigation = find.byType(NavigationBar);
  expect(navigation, findsOneWidget);
  final target = find.descendant(of: navigation, matching: find.byIcon(icon));
  expect(target, findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Widget _testApp({MemoryAppPreferencesStore? preferencesStore}) {
  return QuantaraApp(
    repository: const FakeOwnerAlphaRepository(),
    settingsStore: MemoryOwnerAlphaSettingsStore(),
    preferencesStore: preferencesStore ?? MemoryAppPreferencesStore(),
    opportunityStateStore: MemoryOpportunityStateStore(),
    notificationGateway: RecordingSetupNotificationGateway(),
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
