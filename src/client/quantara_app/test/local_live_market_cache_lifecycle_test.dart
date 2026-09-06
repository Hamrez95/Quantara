import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Local Live retains one candle-analysis cache for the armed session',
    () {
      final source = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('BitunixOwnerAlphaRepository? _marketRepository'),
      );
      expect(
        source,
        contains('_marketRepository = BitunixOwnerAlphaRepository'),
      );
      expect(source, contains('final repository = _marketRepository;'));
      expect(
        source,
        isNot(
          contains(
            'final client = http.Client();\n    try {\n      final repository',
          ),
        ),
      );
      expect(source, contains('_marketHttpClient?.close();'));
    },
  );
}
