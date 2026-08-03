import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';
import 'package:quantara_app/features/trading_journal/presentation/trading_journal_view.dart';

void main() {
  TradingJournalProjection fixture({
    required String id,
    required TradingJournalTradeState state,
    required String symbol,
    required double? net,
  }) => TradingJournalProjection.fixture(
    journalTradeId: id,
    symbol: symbol,
    timeframe: '15m',
    strategy: 'structure',
    direction: TradingJournalDirection.short,
    source: TradingJournalSource.localLive,
    state: state,
    netPnl: net,
    realizedR: net == null ? null : net / 0.5,
    closeReason: state == TradingJournalTradeState.closed
        ? TradingJournalCloseReason.stop
        : null,
    decidedAt: DateTime.utc(2026, 8, 3, 10),
    closedAt: state == TradingJournalTradeState.closed
        ? DateTime.utc(2026, 8, 3, 11)
        : null,
    timeline: [
      TradingJournalEvent(
        eventId: '$id-entry',
        journalTradeId: id,
        type: TradingJournalEventType.entryFilled,
        occurredAt: DateTime.utc(2026, 8, 3, 10, 1),
        recordedAt: DateTime.utc(2026, 8, 3, 10, 1, 1),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: 'USDT',
        asOf: DateTime.utc(2026, 8, 3, 10, 1),
        exchangeEventId: '$id-trade-entry',
        positionId: '$id-position',
        orderId: '$id-order-entry',
        tradeId: '$id-trade-entry',
        quantity: 21.4,
        price: 1.0665,
        remainingQuantity: 21.4,
      ),
      if (state == TradingJournalTradeState.closed)
        TradingJournalEvent(
          eventId: '$id-close',
          journalTradeId: id,
          type: TradingJournalEventType.positionClosed,
          occurredAt: DateTime.utc(2026, 8, 3, 11),
          recordedAt: DateTime.utc(2026, 8, 3, 11, 0, 1),
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: 'USDT',
          asOf: DateTime.utc(2026, 8, 3, 11),
          exchangeEventId: '$id-trade-close',
          positionId: '$id-position',
          orderId: '$id-order-close',
          tradeId: '$id-trade-close',
          quantity: 21.4,
          price: 1.0691,
          grossPnl: net,
          fee: 0,
          funding: 0,
          remainingQuantity: 0,
          details: const {'closeReason': 'stop'},
        ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    required Locale locale,
    required List<TradingJournalProjection> projections,
    bool loading = false,
    String? error,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      home: Scaffold(
        body: TradingJournalView(
          locale: locale,
          projections: projections,
          isLoading: loading,
          error: error,
        ),
      ),
    ),
  );

  testWidgets('Persian journal is RTL and opens ordered position timeline', (
    tester,
  ) async {
    await pump(
      tester,
      locale: const Locale('fa'),
      projections: [
        fixture(
          id: 'closed-xrp',
          state: TradingJournalTradeState.closed,
          symbol: 'XRPUSDT',
          net: 0.031,
        ),
      ],
    );

    expect(find.text('ژورنال معاملات'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('ژورنال معاملات'))),
        TextDirection.rtl);
    expect(find.text('XRPUSDT'), findsOneWidget);
    expect(find.textContaining('0.031'), findsOneWidget);

    await tester.tap(find.text('XRPUSDT'));
    await tester.pumpAndSettle();

    expect(find.text('تایم‌لاین پوزیشن'), findsOneWidget);
    expect(find.textContaining('Entry'), findsOneWidget);
    expect(find.textContaining('Close'), findsOneWidget);
    final entryY = tester.getTopLeft(find.textContaining('Entry').first).dy;
    final closeY = tester.getTopLeft(find.textContaining('Close').first).dy;
    expect(entryY, lessThan(closeY));
  });

  testWidgets('English journal is LTR and filters open/closed records', (
    tester,
  ) async {
    await pump(
      tester,
      locale: const Locale('en'),
      projections: [
        fixture(
          id: 'open-btc',
          state: TradingJournalTradeState.open,
          symbol: 'BTCUSDT',
          net: null,
        ),
        fixture(
          id: 'closed-xrp',
          state: TradingJournalTradeState.closed,
          symbol: 'XRPUSDT',
          net: -0.2,
        ),
      ],
    );

    expect(find.text('Trading Journal'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('Trading Journal'))),
        TextDirection.ltr);
    expect(find.text('BTCUSDT'), findsOneWidget);
    expect(find.text('XRPUSDT'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('BTCUSDT'), findsOneWidget);
    expect(find.text('XRPUSDT'), findsNothing);
  });

  testWidgets('empty, loading and error states are explicit', (tester) async {
    await pump(
      tester,
      locale: const Locale('en'),
      projections: const [],
      loading: true,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pump(
      tester,
      locale: const Locale('en'),
      projections: const [],
      error: 'Journal integrity check failed.',
    );
    expect(find.textContaining('integrity'), findsOneWidget);

    await pump(
      tester,
      locale: const Locale('en'),
      projections: const [],
    );
    expect(find.text('No journal records yet.'), findsOneWidget);
  });
}
