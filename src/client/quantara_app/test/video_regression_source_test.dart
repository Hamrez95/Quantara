import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'video regressions stay wired to bounded leverage and sizing refresh',
    () {
      final signals = File(
        'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/features/owner_alpha/application/owner_alpha_controller.dart',
      ).readAsStringSync();
      final background = File(
        'lib/features/owner_alpha/data/background_opportunity_scanner.dart',
      ).readAsStringSync();
      expect(signals, isNot(contains('Slider(')));
      expect(signals, contains('سرمایه مبنای محاسبه'));
      expect(signals, contains('بودجه ریسک'));
      expect(controller, contains('SignalSizingReconciler.merge'));
      expect(
        controller,
        contains('await _captureOpportunities(_snapshot!.opportunities)'),
      );
      expect(background, contains('SignalSizingReconciler.merge'));
    },
  );
}
