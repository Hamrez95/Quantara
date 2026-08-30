import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/presentation/actionable_signal_presentation.dart';

void main() {
  final now = DateTime.utc(2026, 8, 18, 10);

  test('projects forming and armed states from persisted pending evidence', () {
    final forming = ActionableSignalPresentation.fromEvidence(
      entry: _entry(),
      nowUtc: now,
      marketDataFresh: true,
      currentPrice: 97,
      quoteObservedAtUtc: now.subtract(const Duration(seconds: 12)),
    );
    final armed = ActionableSignalPresentation.fromEvidence(
      entry: _entry(),
      nowUtc: now,
      marketDataFresh: true,
      currentPrice: 99.5,
      quoteObservedAtUtc: now,
    );

    expect(forming.stage, ActionableSignalStage.forming);
    expect(forming.distanceToEntryPercent, closeTo(2.0618, 0.0001));
    expect(forming.marketAge, const Duration(seconds: 12));
    expect(armed.stage, ActionableSignalStage.armed);
    expect(armed.distanceToEntryPercent, 0);
    expect(
      armed.conciseReason(persian: true),
      contains('تریگر بسته‌شده هنوز تأیید نشده'),
    );
  });

  test('fails closed when current public market evidence is unavailable', () {
    final result = ActionableSignalPresentation.fromEvidence(
      entry: _entry(),
      nowUtc: now,
      marketDataFresh: false,
    );

    expect(result.stage, ActionableSignalStage.dataUncertain);
    expect(result.isDataUncertain, isTrue);
    expect(result.distanceLabel(persian: false), 'Unknown');
    expect(result.safeNextAction(persian: true), 'تا تازه‌شدن داده اقدام نکن');
    expect(result.rawReasonCode, 'market-data-uncertain:pendingEntry');
  });

  test('maps domain outcomes without presenting a fabricated probability', () {
    final cases = <SignalOutcome, ActionableSignalStage>{
      SignalOutcome.active: ActionableSignalStage.triggered,
      SignalOutcome.tp1: ActionableSignalStage.managing,
      SignalOutcome.tp2: ActionableSignalStage.managing,
      SignalOutcome.expiredUntriggered: ActionableSignalStage.missed,
      SignalOutcome.stopped: ActionableSignalStage.resolved,
      SignalOutcome.tp3: ActionableSignalStage.resolved,
    };

    for (final item in cases.entries) {
      final result = ActionableSignalPresentation.fromEvidence(
        entry: _entry(outcome: item.key),
        nowUtc: now,
        marketDataFresh: true,
        currentPrice: 99.5,
        quoteObservedAtUtc: now,
      );
      expect(result.stage, item.value, reason: item.key.name);
      expect(result.rawReasonCode, 'signal-outcome:${item.key.name}');
      expect(result.conciseReason(persian: false), isNot(contains('%')));
    }
  });

  test(
    'expired pending evidence becomes missed and future clock skew is safe',
    () {
      final result = ActionableSignalPresentation.fromEvidence(
        entry: _entry(validUntil: now.subtract(const Duration(seconds: 1))),
        nowUtc: now,
        marketDataFresh: true,
        currentPrice: 101,
        quoteObservedAtUtc: now.add(const Duration(seconds: 5)),
      );

      expect(result.stage, ActionableSignalStage.missed);
      expect(result.marketAge, Duration.zero);
      expect(result.safeNextAction(persian: false), 'Do not enter now');
    },
  );
}

SignalJournalEntry _entry({
  SignalOutcome outcome = SignalOutcome.pendingEntry,
  DateTime? validUntil,
}) => SignalJournalEntry(
  setupId: 'BTCUSDT|15m|long|test',
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test-v1',
  createdAt: DateTime.utc(2026, 8, 18, 9),
  validUntil: validUntil ?? DateTime.utc(2026, 8, 18, 11),
  entryLower: 99,
  entryUpper: 100,
  stopLoss: 98,
  targets: const [102, 104],
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.1,
  recommendedLeverage: 2,
  maximumSafeLeverage: 3,
  selectedLeverage: 2,
  summary: 'test setup',
  invalidation: 'below 98',
  confidencePercent: 91,
  setupQualityScore: null,
  outcome: outcome,
);
