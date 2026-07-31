import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/layout/trading_workspace_layout.dart';

Widget app({required double width, bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 900),
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: SizedBox(
          width: width,
          height: 900,
          child: TradingWorkspaceScaffold(
            header: const QuantaraCockpitHeader(
              title: 'Quantara',
              workspace: 'BTCUSDT · 1h',
              modeLabel: 'APPROVAL',
              modeColor: Colors.orange,
            ),
            marketPane: const ColoredBox(
              key: ValueKey('market-pane'),
              color: Colors.black12,
            ),
            chartPane: const ColoredBox(
              key: ValueKey('chart-pane'),
              color: Colors.black26,
            ),
            setupPane: const ColoredBox(
              key: ValueKey('setup-pane'),
              color: Colors.black38,
            ),
            positionsPane: const ColoredBox(
              key: ValueKey('positions-pane'),
              color: Colors.black45,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('desktop keeps all trading panes visible', (tester) async {
    await tester.pumpWidget(app(width: 1440));

    expect(find.byKey(const ValueKey('market-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('positions-pane')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile uses pane navigation instead of stacking dense data', (
    tester,
  ) async {
    await tester.pumpWidget(app(width: 390));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('market-pane')), findsNothing);

    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('market-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-pane')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps pane changes deterministic', (
    tester,
  ) async {
    await tester.pumpWidget(app(width: 390, disableAnimations: true));

    await tester.tap(find.text('Positions'));
    await tester.pump();

    expect(find.byKey(const ValueKey('positions-pane')), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
