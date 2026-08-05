from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text or text.count(old) != 1:
        raise SystemExit(f'anchor missing or non-unique in {path}: {old[:90]!r}')
    path.write_text(text.replace(old, new, 1))


runtime = ROOT / 'lib/features/auto_trade/application/local_live_portfolio_risk_runtime.dart'
adopt_method = r'''  Future<PortfolioRiskLedger> adoptVerifiedOpenPosition({
    required LocalLiveManagedPosition managed,
    required double confirmedStop,
    required DateTime now,
  }) => _atomicStore.mutate<PortfolioRiskLedger>((current) async {
    final base = _normalize(current, now.toUtc());
    final positionId = managed.positionId.trim();
    if (positionId.isEmpty ||
        managed.initialQuantity <= 0 ||
        managed.entryPrice <= 0 ||
        confirmedStop <= 0 ||
        managed.leverage <= 0) {
      throw const LocalLiveTradeSafeException(
        'Recovered position risk facts are invalid.',
      );
    }
    final matching = base.activeReservations
        .where((item) => item.positionId == positionId)
        .toList(growable: false);
    final existingVerified = matching.where(
      (item) =>
          item.open &&
          item.verification == PortfolioVerificationState.exchangeConfirmed,
    );
    if (existingVerified.isNotEmpty) {
      final existing = existingVerified.single;
      if (existing.symbol.toUpperCase() == managed.symbol.toUpperCase() &&
          (existing.filledQuantity - managed.initialQuantity).abs() <= 1e-9) {
        return PortfolioRiskLedgerMutation(value: base, nextLedger: base);
      }
      throw const LocalLiveTradeSafeException(
        'A conflicting verified reservation already owns this position.',
      );
    }
    if (matching.any(
      (item) => !item.reservationId.startsWith('external-unmanaged:'),
    )) {
      throw const LocalLiveTradeSafeException(
        'A conflicting risk reservation prevents safe recovery.',
      );
    }
    if (base.activeReservations.any(
      (item) =>
          item.positionId != positionId &&
          item.symbol.toUpperCase() == managed.symbol.toUpperCase(),
    )) {
      throw const LocalLiveTradeSafeException(
        'Another active reservation already uses the recovered symbol.',
      );
    }

    final notional = managed.initialQuantity * managed.entryPrice;
    final entryFee = notional * 0.0006;
    final exitFee = managed.initialQuantity * confirmedStop * 0.0006;
    final slippage = notional * 0.0008;
    final fundingReserve = notional * 0.0003;
    final side = managed.direction == TradeDirection.long
        ? PortfolioSide.long
        : PortfolioSide.short;
    final maximumLoss = PortfolioRiskMath.confirmedOpenRisk(
      side: side,
      entryPrice: managed.entryPrice,
      confirmedStop: confirmedStop,
      remainingQuantity: managed.initialQuantity,
      contractMultiplier: 1,
      entryFee: entryFee,
      exitFee: exitFee,
      slippageReserve: slippage,
      fundingReserve: fundingReserve,
    );
    final observedMargin = notional / managed.leverage;
    final retained = base.reservations
        .where(
          (item) =>
              !(item.positionId == positionId &&
                  item.reservationId.startsWith('external-unmanaged:')),
        )
        .toList(growable: false);
    final reservation = PositionRiskReservation(
      reservationId: 'recovered-local-live:$positionId',
      journalTradeId: 'local-live:$positionId',
      candidateId: managed.setupId,
      symbol: managed.symbol.toUpperCase(),
      assetGroup: LocalLivePortfolioAdmission.assetGroupForSymbol(
        managed.symbol,
      ),
      side: side,
      strategy: 'recovered-local-live',
      entryOrderId: managed.entryOrderId,
      positionId: positionId,
      plannedQuantity: managed.initialQuantity,
      filledQuantity: managed.initialQuantity,
      entryPrice: managed.entryPrice,
      currentExchangeConfirmedStop: confirmedStop,
      contractMultiplier: 1,
      estimatedEntryFee: entryFee,
      estimatedExitFee: exitFee,
      slippageReserve: slippage,
      fundingReserve: fundingReserve,
      maximumLoss: maximumLoss,
      reservedMargin: observedMargin,
      createdAt: managed.openedAt.toUtc(),
      tradingDayId: base.tradingDay.value,
      lifecycle: PortfolioReservationLifecycle.open,
      verification: PortfolioVerificationState.exchangeConfirmed,
      revision: 1,
    );
    final next = PortfolioRiskLedger(
      schemaVersion: base.schemaVersion,
      revision: base.revision + 1,
      tradingDay: base.tradingDay,
      dailyRiskLimit: base.dailyRiskLimit,
      realizedLoss: base.realizedLoss,
      realizedProfit: base.realizedProfit,
      reservations: [...retained, reservation],
      processedEventIds: {
        ...base.processedEventIds,
        'recover-open:$positionId',
      },
    );
    return PortfolioRiskLedgerMutation(value: next, nextLedger: next);
  });

'''
replace_once(runtime, '  Future<PortfolioRiskLedger> release({\n', adopt_method + '  Future<PortfolioRiskLedger> release({\n')

observer = ROOT / 'lib/features/trading_journal/application/local_live_journal_observer.dart'
observer_method = r'''  Future<bool> recordRecoveredPosition({
    required LocalLiveManagedPosition managed,
    required AutoTradeAccountSnapshot account,
  }) async {
    final id = journalTradeId(managed.positionId);
    final riskPerUnit = (managed.entryPrice - managed.originalStopLoss).abs();
    final expectedR = managed.targets
        .map(
          (target) => riskPerUnit <= 0
              ? 0.0
              : (target - managed.entryPrice).abs() / riskPerUnit,
        )
        .toList(growable: false);
    final riskBudget =
        riskPerUnit * managed.initialQuantity +
        managed.entryPrice * managed.initialQuantity * 0.0017;
    final riskPercent = account.estimatedEquity <= 0
        ? 0.0
        : riskBudget / account.estimatedEquity * 100;
    final plan = TradingJournalPlan(
      journalTradeId: id,
      setupId: managed.setupId,
      analysisVersion: 'exchange-recovery-v1',
      symbol: managed.symbol,
      market: 'USDT_PERPETUAL',
      timeframe: managed.timeframe,
      direction: _direction(managed.direction),
      strategy: 'recovered-local-live',
      cadence: 'recovered-after-reinstall',
      source: TradingJournalSource.localLive,
      decidedAt: managed.openedAt.toUtc(),
      decisionPrice: managed.entryPrice,
      entryLower: managed.entryPrice,
      entryUpper: managed.entryPrice,
      plannedEntry: managed.entryPrice,
      originalStopLoss: managed.originalStopLoss,
      targets: List.unmodifiable(managed.targets),
      expectedRMultiples: List.unmodifiable(expectedR),
      confidencePercent: 0,
      confluence: const [
        'verified-q-local-entry-order',
        'verified-open-position-id',
        'confirmed-full-stop',
        'confirmed-three-target-ladder',
      ],
      regime: 'recovered-exchange-truth',
      rationale:
          'Recovered from verified Bitunix position, fill and protection facts after device-local state was removed.',
      invalidation:
          'Original signal metadata was unavailable after reinstall; no value was fabricated.',
      accountEquity: account.estimatedEquity,
      riskPercent: riskPercent,
      riskBudget: riskBudget,
      leverage: managed.leverage,
      expectedMargin:
          managed.initialQuantity * managed.entryPrice / managed.leverage,
      passedGates: const [
        'isolated-margin',
        'verified-q-local-entry-order',
        'confirmed-full-stop',
        'confirmed-three-target-ladder',
        'no-confirmed-partial-exit',
      ],
      blockedGates: const [],
      appVersion: '1.2.0-rc.2+121',
      strategyRulesVersion: 'exchange-recovery-v1',
      positionId: managed.positionId,
      entryOrderId: managed.entryOrderId,
      clientId: managed.clientId,
      notes:
          'Recovered after app reinstall. Original signal confidence and timeframe were not reconstructed.',
    );
    if (!await _appendPlan(plan)) return false;

    final now = DateTime.now().toUtc();
    await _append(
      TradingJournalEvent(
        eventId: 'recovered-entry:${managed.entryOrderId}',
        journalTradeId: id,
        type: TradingJournalEventType.entryFilled,
        occurredAt: managed.openedAt.toUtc(),
        recordedAt: now,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: account.syncedAt.toUtc(),
        exchangeEventId: 'entry-order:${managed.entryOrderId}',
        positionId: managed.positionId,
        orderId: managed.entryOrderId,
        clientId: managed.clientId,
        quantity: managed.initialQuantity,
        price: managed.entryPrice,
        remainingQuantity: managed.initialQuantity,
        details: const {
          'marginMode': 'ISOLATION',
          'recoveredAfterReinstall': true,
        },
      ),
    );
    await _append(
      TradingJournalEvent(
        eventId: 'recovered-stop:${managed.stopOrderId}',
        journalTradeId: id,
        type: TradingJournalEventType.stopConfirmed,
        occurredAt: now,
        recordedAt: now,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: account.syncedAt.toUtc(),
        exchangeEventId: 'stop-order:${managed.stopOrderId}',
        positionId: managed.positionId,
        orderId: managed.stopOrderId,
        quantity: managed.initialQuantity,
        price: managed.originalStopLoss,
      ),
    );
    for (var index = 0; index < managed.targetOrderIds.length; index++) {
      await _append(
        TradingJournalEvent(
          eventId: 'recovered-tp:${managed.targetOrderIds[index]}',
          journalTradeId: id,
          type: TradingJournalEventType.takeProfitConfirmed,
          occurredAt: now,
          recordedAt: now,
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: account.marginCoin,
          asOf: account.syncedAt.toUtc(),
          exchangeEventId: 'tp-order:${managed.targetOrderIds[index]}',
          positionId: managed.positionId,
          orderId: managed.targetOrderIds[index],
          quantity: managed.targetQuantities[index],
          price: managed.targets[index],
          details: {'targetIndex': index + 1},
        ),
      );
    }
    await _append(
      TradingJournalEvent(
        eventId: 'recovered:${managed.positionId}',
        journalTradeId: id,
        type: TradingJournalEventType.reconciliationRecovered,
        occurredAt: now,
        recordedAt: now,
        source: TradingJournalFactSource.quantara,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: account.syncedAt.toUtc(),
        exchangeEventId: 'recovered-position:${managed.positionId}',
        positionId: managed.positionId,
        details: const {
          'message':
              'Device-local ownership was reconstructed from verified exchange truth after reinstall.',
        },
      ),
    );
    return true;
  }

'''
replace_once(observer, '  Future<void> reconcilePosition({\n', observer_method + '  Future<void> reconcilePosition({\n')

print('issue 166 risk and journal patch applied')
