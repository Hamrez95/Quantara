import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'critical hot-path primitives remain isolated from slow dependencies',
    () {
      const paths = [
        'lib/features/hot_path_performance/domain/rolling_market_features.dart',
        'lib/features/hot_path_performance/domain/hot_path_latency.dart',
        'lib/features/owner_alpha/data/realtime_market_event_bus.dart',
      ];
      const forbidden = [
        'ai_supervisor',
        'openai',
        'presentation/',
        'dart:io',
        'shared_preferences',
        'http.dart',
      ];

      for (final path in paths) {
        final source = File(path).readAsStringSync().toLowerCase();
        for (final token in forbidden) {
          expect(
            source,
            isNot(contains(token)),
            reason: '$path imports $token',
          );
        }
      }
    },
  );
}
