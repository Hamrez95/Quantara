import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'paper execution realizes partial fills and latency after canonical decision',
    () {
      final source = File(
        'lib/features/trading_lab/application/trading_lab_paper_broker.dart',
      ).readAsStringSync();

      final canonicalIndex = source.indexOf(
        'evaluateTradingLabCanonicalDecision',
      );
      final partialFillIndex = source.indexOf('manifest.partialFillRatio');
      final latencyIndex = source.indexOf('manifest.latencyPenaltyBps');
      expect(canonicalIndex, greaterThanOrEqualTo(0));
      expect(partialFillIndex, greaterThan(canonicalIndex));
      expect(latencyIndex, greaterThan(canonicalIndex));
      expect(source, contains("'plannedQuantity': plannedQuantity"));
      expect(source, contains("'latencyCost': latencyCost"));
      expect(source, contains("'fillModel':"));
    },
  );

  test(
    'live execution path is not modified by Trading Lab fill assumptions',
    () {
      final live = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();
      expect(live, isNot(contains('partialFillRatio')));
      expect(live, isNot(contains('latencyPenaltyBps')));
      expect(live, contains('portfolioGuard.reserve'));
      expect(live, contains('exchange.placeMarketEntry'));
    },
  );
}
