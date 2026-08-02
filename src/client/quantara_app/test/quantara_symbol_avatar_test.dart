import 'package:crypto_icons/crypto_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/widgets/quantara_ui.dart';

void main() {
  testWidgets('shows a local Bitcoin identity without network assets', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SymbolAvatar(symbol: 'BTCUSDT')),
      ),
    );

    expect(find.byIcon(CryptoIcons.fromSymbol('BTC')), findsOneWidget);
    expect(find.byType(SymbolAvatar), findsOneWidget);
  });

  testWidgets('unknown symbols receive a deterministic monogram', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SymbolAvatar(symbol: 'ABCUSDT')),
      ),
    );

    expect(find.text('AB'), findsOneWidget);
  });
}
