import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/presentation/tp_allocation_editor.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  testWidgets('TP1 plus changes 65/20/15 to 70/20/10 and keeps total 100', (
    tester,
  ) async {
    var allocation = ProfitProtectionTargetAllocation.standard;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TpAllocationEditor(
              allocation: allocation,
              persian: false,
              onChanged: (value) => setState(() => allocation = value),
            ),
          ),
        ),
      ),
    );

    expect(find.text('65%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('15%'), findsOneWidget);
    expect(find.text('Total: 100%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tp1-plus')));
    await tester.pump();

    expect(find.text('70%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(
      allocation.fractions.fold<double>(0, (sum, value) => sum + value),
      closeTo(1, 0.000001),
    );
  });

  testWidgets('disabled allocation editor cannot mutate an armed plan', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TpAllocationEditor(
            allocation: ProfitProtectionTargetAllocation.standard,
            persian: true,
            enabled: false,
            onChanged: (_) => calls++,
          ),
        ),
      ),
    );

    final plus = tester.widget<IconButton>(
      find.byKey(const ValueKey('tp1-plus')),
    );
    expect(plus.onPressed, isNull);
    expect(calls, 0);
  });
}
