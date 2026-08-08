import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'journal UI exposes closed pending economics and evidence review sections',
    () {
      final source = File(
        'lib/features/trading_journal/presentation/trading_journal_view.dart',
      ).readAsStringSync();
      expect(source, contains('PnL reconciliation pending'));
      expect(source, contains('Why entered?'));
      expect(source, contains('Why exited?'));
      expect(source, contains('What to review?'));
      expect(source, contains('Data quality'));
      expect(source, contains('_formatHoldingDuration'));
    },
  );
}
