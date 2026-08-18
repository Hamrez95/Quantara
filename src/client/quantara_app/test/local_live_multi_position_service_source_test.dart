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

  test('service reserves and records timing before submitting an entry', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    final reserve = source.indexOf('portfolioGuard.reserve(');
    final submitTiming = source.indexOf(
      'privateTruth.recordOrderSubmission(correlationId: clientId);',
    );
    final submit = source.indexOf('exchange.placeMarketEntry(');

    expect(reserve, greaterThanOrEqualTo(0));
    expect(submitTiming, greaterThan(reserve));
    expect(submit, greaterThan(submitTiming));
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

  test('blocked top-ranked setup cannot starve lower-ranked symbols', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('final rankedIdeas = LocalLiveEconomicRanking.rank('),
    );
    expect(source, contains('for (final rankedIdea in rankedIdeas)'));
    expect(source, contains('final idea = rankedIdea.idea;'));
    expect(source, contains('OpportunityRankingOutcome.canonicalRejected'));
    expect(source, contains('OpportunityRankingOutcome.portfolioRejected'));
    expect(source, contains("'scan_candidates_exhausted'"));

    final canonicalBlock = source.indexOf('if (!canonical.eligible)');
    final canonicalContinue = source.indexOf('continue;', canonicalBlock);
    final reservationBlock = source.indexOf("'portfolio_reservation_block'");
    final reservationContinue = source.indexOf('continue;', reservationBlock);
    expect(canonicalBlock, greaterThanOrEqualTo(0));
    expect(canonicalContinue, greaterThan(canonicalBlock));
    expect(reservationBlock, greaterThan(canonicalContinue));
    expect(reservationContinue, greaterThan(reservationBlock));

    final protected = source.indexOf("'position_protected'");
    final successfulReturn = source.indexOf('return;', protected);
    expect(protected, greaterThanOrEqualTo(0));
    expect(successfulReturn, greaterThan(protected));
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