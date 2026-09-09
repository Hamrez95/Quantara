import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/presentation/setup_performance_report.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

// Regression coverage for #527: reporting stays read-only and evidence-first.
void main() {
  final now = DateTime.utc(2026, 9, 7, 12);

  Widget harness({
    List<SignalJournalEntry> signals = const [],
    bool loading = false,
    String? error,
    ValueChanged<SignalJournalEntry>? onOpen,
  }) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SetupPerformanceReportSheet(
          signals: signals,
          projections: const <TradingJournalProjection>[],
          isJournalLoading: loading,
          journalError: error,
          onOpenSetup: onOpen ?? (_) {},
          now: now,
        ),
      ),
    ),
  );

  Future<void> scrollDownTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders Persian RTL and empty real-performance state', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    final report = find.byKey(const Key('setup-performance-report'));
    expect(report, findsOneWidget);
    expect(Directionality.of(tester.element(report)), TextDirection.rtl);
    expect(find.text('گزارش عملکرد ستاپ‌ها'), findsOneWidget);

    final realSummary = find.byKey(const Key('actual-performance-summary'));
    await scrollDownTo(tester, realSummary);
    expect(realSummary, findsOneWidget);
    expect(
      find.textContaining('عملکرد واقعی صرافی برای این ستاپ‌ها موجود نیست'),
      findsOneWidget,
    );

    final empty = find.byKey(const Key('setup-performance-empty'));
    await scrollDownTo(tester, empty);
    expect(empty, findsOneWidget);
  });

  testWidgets('renders loading and error states without inventing real PnL', (
    tester,
  ) async {
    await tester.pumpWidget(harness(loading: true));
    expect(find.byKey(const Key('setup-performance-loading')), findsOneWidget);

    await tester.pumpWidget(harness(error: 'reconciliation failed'));
    await tester.pump();
    expect(find.byKey(const Key('setup-performance-error')), findsOneWidget);
    expect(find.textContaining('دادهٔ واقعی قابل تأیید نیست'), findsOneWidget);
  });

  testWidgets('range filter changes visible setup rows', (tester) async {
    final recent = _signal(
      setupId: 'recent',
      resolvedAt: now.subtract(const Duration(days: 2)),
    );
    final old = _signal(
      setupId: 'old',
      resolvedAt: now.subtract(const Duration(days: 10)),
    );
    await tester.pumpWidget(harness(signals: [recent, old]));

    expect(find.byKey(const Key('setup-performance-row-old')), findsNothing);

    await tester.tap(find.byKey(const Key('performance-range-all')));
    await tester.pumpAndSettle();

    final oldRow = find.byKey(const Key('setup-performance-row-old'));
    await scrollDownTo(tester, oldRow);
    expect(oldRow, findsOneWidget);
  });

  testWidgets('drill-down opens the exact setup', (tester) async {
    String? openedSetupId;
    final entry = _signal(setupId: 'drill', resolvedAt: now);
    await tester.pumpWidget(
      harness(
        signals: [entry],
        onOpen: (value) => openedSetupId = value.setupId,
      ),
    );

    final row = find.byKey(const Key('setup-performance-row-drill'));
    await scrollDownTo(tester, row);
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();

    final openButton = find.text('باز کردن ستاپ');
    expect(openButton, findsOneWidget);
    await scrollDownTo(tester, openButton);
    await tester.tap(openButton);
    await tester.pump();

    expect(openedSetupId, 'drill');
  });
}

SignalJournalEntry _signal({
  required String setupId,
  required DateTime resolvedAt,
}) => SignalJournalEntry(
  setupId: setupId,
  symbol: 'BTCUSDT',
  timeframe: '1h',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: '1.0',
  createdAt: resolvedAt.subtract(const Duration(hours: 2)),
  validUntil: resolvedAt.subtract(const Duration(hours: 1)),
  entryLower: 100,
  entryUpper: 101,
  stopLoss: 95,
  targets: const [105, 110, 115],
  maximumLoss: 5,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.2,
  recommendedLeverage: 2,
  maximumSafeLeverage: 5,
  selectedLeverage: 2,
  summary: 'Test setup',
  invalidation: 'Test invalidation',
  confidencePercent: 70,
  riskReward: 2,
  outcome: SignalOutcome.tp3,
  highestTargetHit: 3,
  activatedAt: resolvedAt.subtract(const Duration(minutes: 90)),
  resolvedAt: resolvedAt,
  priceChangePercent: 5,
  simulatedPnl: 5,
  marginReturnPercent: 5,
);
