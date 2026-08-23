import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/profit_lock_stop_policy.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('long runner never widens after a pullback', () {
    final first = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.long,
      markPrice: 120,
      currentConfirmedStop: 110,
      tp1Price: 108,
      initialRiskDistance: 5,
      pricePrecision: 2,
      previousFavorableExtreme: 118,
    );
    expect(first.favorableExtreme, 120);
    expect(first.stopDecision.proposedStop, greaterThanOrEqualTo(110));

    final pullback = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.long,
      markPrice: 112,
      currentConfirmedStop: first.stopDecision.proposedStop,
      tp1Price: 108,
      initialRiskDistance: 5,
      pricePrecision: 2,
      previousFavorableExtreme: first.favorableExtreme,
    );
    expect(pullback.favorableExtreme, 120);
    expect(
      pullback.stopDecision.proposedStop,
      first.stopDecision.proposedStop,
    );
    expect(pullback.stopDecision.requiresMutation, isFalse);
  });

  test('short runner never widens and preserves favorable low', () {
    final first = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.short,
      markPrice: 80,
      currentConfirmedStop: 90,
      tp1Price: 92,
      initialRiskDistance: 5,
      pricePrecision: 2,
      previousFavorableExtreme: 82,
    );
    expect(first.favorableExtreme, 80);
    expect(first.stopDecision.proposedStop, lessThanOrEqualTo(90));

    final rebound = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.short,
      markPrice: 88,
      currentConfirmedStop: first.stopDecision.proposedStop,
      tp1Price: 92,
      initialRiskDistance: 5,
      pricePrecision: 2,
      previousFavorableExtreme: first.favorableExtreme,
    );
    expect(rebound.favorableExtreme, 80);
    expect(rebound.stopDecision.proposedStop, first.stopDecision.proposedStop);
  });

  test('trusted ATR drives chandelier distance when available', () {
    final decision = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.long,
      markPrice: 120,
      currentConfirmedStop: 108,
      tp1Price: 107,
      initialRiskDistance: 10,
      atr: 2,
      pricePrecision: 2,
    );

    expect(decision.usedAtr, isTrue);
    expect(decision.stopDecision.proposedStop, 115);
  });

  test('validated swing or structure level can only tighten the runner', () {
    final decision = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.long,
      markPrice: 120,
      currentConfirmedStop: 108,
      tp1Price: 107,
      initialRiskDistance: 8,
      swingStop: 114,
      structureStop: 116,
      pricePrecision: 2,
    );

    expect(decision.stopDecision.proposedStop, 116);
    expect(decision.stopDecision.requiresMutation, isTrue);
  });

  test('5m scalp profile trails tighter than standard fallback', () {
    final standard = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.long,
      markPrice: 120,
      currentConfirmedStop: 105,
      tp1Price: 106,
      initialRiskDistance: 8,
      pricePrecision: 2,
    );
    final scalp = ProfitLockStopPolicy.runnerTrail(
      direction: TradeDirection.long,
      markPrice: 120,
      currentConfirmedStop: 105,
      tp1Price: 106,
      initialRiskDistance: 8,
      pricePrecision: 2,
      scalp: true,
    );

    expect(scalp.stopDecision.proposedStop, greaterThan(standard.stopDecision.proposedStop));
  });

  test('runner favorable extreme survives durable restart round trip', () {
    const progress = ProfitLockProgress(
      confirmedStage: 2,
      processedTradeIds: {'tp1', 'tp2'},
      runnerFavorableExtreme: 123.45,
    );

    final restored = ProfitLockProgress.fromJson(progress.toJson());

    expect(restored.confirmedStage, 2);
    expect(restored.processedTradeIds, {'tp1', 'tp2'});
    expect(restored.runnerFavorableExtreme, 123.45);
  });
}
