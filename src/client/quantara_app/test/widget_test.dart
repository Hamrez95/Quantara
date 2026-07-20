import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/cockpit/data/mock_cockpit_repository.dart';
import 'package:quantara_app/features/cockpit/domain/cockpit_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a concise and unmistakable demo dashboard', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('نسخه آزمایشی'), findsWidgets);
    expect(find.text('عدم معامله'), findsOneWidget);
    expect(find.text('BTCUSDT'), findsWidgets);
    expect(find.text('معامله با پول واقعی غیرفعال است'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deep mobile scrolling never produces a layout exception', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    final list = find.byType(ListView);
    expect(list, findsOneWidget);

    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.drag(list, const Offset(0, -520));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.drag(list, const Offset(0, 520));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('theme can be toggled repeatedly without assertions', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    for (var attempt = 0; attempt < 8; attempt++) {
      final tooltip = attempt.isEven ? 'حالت روشن' : 'حالت تیره';
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('small phone with larger text remains stable', (tester) async {
    _setViewport(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('عدم معامله'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('market selection changes the dynamic chart source', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('بازار'));
    await tester.pump();
    expect(find.text('BTCUSDT'), findsWidgets);

    final ethereum = find.text('ETHUSDT').last;
    await tester.ensureVisible(ethereum);
    await tester.pumpAndSettle();
    await tester.tap(ethereum);
    await tester.pump();
    expect(find.text('ETHUSDT'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses side navigation on a desktop-sized viewport', (
    tester,
  ) async {
    _setViewport(tester, const Size(1440, 1000));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps loading and loaded states explicit', (tester) async {
    final repository = _ControlledRepository();
    _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(QuantaraApp(repository: repository));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('عدم معامله'), findsNothing);

    repository.complete(MockCockpitRepository.demoSnapshot);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('عدم معامله'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final class _ControlledRepository implements CockpitRepository {
  final Completer<CockpitSnapshot> _completer = Completer<CockpitSnapshot>();

  @override
  Future<CockpitSnapshot> load() => _completer.future;

  void complete(CockpitSnapshot snapshot) {
    _completer.complete(snapshot);
  }
}
