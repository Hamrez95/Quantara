import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'signal leverage uses bounded inline controls instead of dropdown menus',
    () {
      final signals = File(
        'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
      ).readAsStringSync();
      final analysis = File(
        'lib/features/owner_alpha/presentation/owner_alpha_analysis.dart',
      ).readAsStringSync();

      expect(
        signals,
        contains('class _LeverageControl extends StatefulWidget'),
      );
      expect(signals, isNot(contains('DropdownButtonFormField<int>')));
      expect(signals, isNot(contains('Slider(')));
      expect(signals, contains(r"ValueKey('leverage-${entry.setupId}')"));
      expect(signals, contains('IconButton.filledTonal'));
      expect(analysis, isNot(contains('DropdownButtonFormField<int>')));
      expect(analysis, contains('SegmentedButton<String>'));
    },
  );
}
