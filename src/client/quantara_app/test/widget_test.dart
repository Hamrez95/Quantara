import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/cockpit/data/mock_cockpit_repository.dart';
import 'package:quantara_app/features/cockpit/domain/cockpit_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows an unmistakable demo cockpit and no-trade decision', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('محیط آزمایشی'), findsWidgets);
    expect(find.text('عدم معامله'), findsWidgets);
    expect(find.text('BTCUSDT'), findsWidgets);
    expect(find.text('معامله با پول واقعی قفل است'), findsOneWidget);
    expect(find.textContaining('هیچ سفارش واقعی'), findsOneWidget);
  });

  testWidgets('uses bottom navigation on a phone-sized viewport', (tester) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses side navigation on a desktop-sized viewport', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 1000));
    await tester.pumpWidget(const QuantaraApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps loading and loaded states explicit', (tester) async {
    final repository = _ControlledRepository();
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(QuantaraApp(repository: repository));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('عدم معامله'), findsNothing);

    repository.complete(await const MockCockpitRepository().load());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('عدم معامله'), findsWidgets);
  });
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
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
