import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('next RC configuration accepts one to three positions only', () {
    for (final maximum in [1, 2, 3]) {
      expect(() => _configuration(maximum).validate(), returnsNormally);
    }
    expect(() => _configuration(0).validate(), throwsFormatException);
    expect(() => _configuration(4).validate(), throwsFormatException);
  });

  test('service reserves atomically before submitting an entry order', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    final reserve = source.indexOf('portfolioGuard.reserve(');
    final submit = source.indexOf('exchange.placeMarketEntry(');

    expect(reserve, greaterThanOrEqualTo(0));
    expect(submit, greaterThan(reserve));
    expect(source, contains('portfolioGuard.recordFill('));
    expect(source, contains('portfolioGuard.confirmStop('));
    expect(source, contains('portfolioGuard.confirmReduction('));
    expect(source, contains('portfolioGuard.markAmbiguous('));
    expect(source, contains('portfolioGuard.releaseNoExposure('));
  });

  test('service scans free slots without same-symbol overlap', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains('_managed.isEmpty &&\n          positions.isEmpty')),
    );
    expect(source, contains('LocalLivePortfolioAdmission.hasExecutionSlot'));
    expect(source, contains('occupiedSymbols'));
    expect(
      source,
      contains('!occupiedSymbols.contains(idea.symbol.trim().toUpperCase())'),
    );
  });
}

LocalLiveTradeConfiguration _configuration(int maximum) =>
    LocalLiveTradeConfiguration(
      symbols: const ['BTCUSDT', 'ETHUSDT'],
      timeframes: const ['1h', '4h'],
      leverage: 3,
      riskPercent: 0.25,
      dailyLossLimitPercent: 3,
      maximumConcurrentPositions: maximum,
      strategy: AnalysisStrategy.structureZones,
      cadence: SignalCadence.balanced,
      languageCode: 'fa',
    );
