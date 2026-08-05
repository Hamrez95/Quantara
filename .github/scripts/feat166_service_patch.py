from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text or text.count(old) != 1:
        raise SystemExit(f'anchor missing or non-unique in {path}: {old[:100]!r}')
    path.write_text(text.replace(old, new, 1))


def replace_between(path: Path, start: str, end: str, new: str) -> None:
    text = path.read_text()
    start_index = text.find(start)
    end_index = text.find(end, start_index + len(start))
    if start_index < 0 or end_index < 0:
        raise SystemExit(f'bounded anchors missing in {path}')
    path.write_text(text[:start_index] + new + text[end_index:])


service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
replace_once(
    service,
    "import 'local_live_portfolio_execution_guard.dart';\nimport 'profit_lock_promotion_executor.dart';\n",
    "import 'local_live_orphan_recovery.dart';\nimport 'local_live_portfolio_execution_guard.dart';\nimport 'profit_lock_promotion_executor.dart';\n",
)
replace_once(
    service,
    "  LocalLivePortfolioBudgetStatus? _portfolioBudget;\n  String? _sessionId;\n",
    "  LocalLivePortfolioBudgetStatus? _portfolioBudget;\n  int _exchangeOpenPositionCount = 0;\n  List<String> _unmanagedSymbols = const [];\n  String? _entryBlockReason;\n  String? _sessionId;\n",
)
replace_once(
    service,
    "      final account = await exchange.fetchAccountSnapshot(credentials);\n      final positions = await exchange.fetchPositions(credentials);\n      _lastExchangeSync = DateTime.now().toUtc();\n      _entriesEnabled = _userRequestedEntries;\n      final sessionId = _sessionId;\n",
    "      final account = await exchange.fetchAccountSnapshot(credentials);\n      final positions = await exchange.fetchPositions(credentials);\n      final openExchangePositions = positions\n          .where((position) => position.quantity > 0)\n          .toList(growable: false);\n      _exchangeOpenPositionCount = openExchangePositions.length;\n      _lastExchangeSync = DateTime.now().toUtc();\n      _entriesEnabled = _userRequestedEntries;\n      _entryBlockReason = null;\n      _sessionStartEquity ??= account.estimatedEquity;\n      if (_sessionStartEquity != null) {\n        await FlutterForegroundTask.saveData(\n          key: localLiveSessionStartEquityKey,\n          value: _sessionStartEquity!,\n        );\n      }\n      if (_sessionStartEquity != null && _sessionStartEquity! > 0) {\n        _portfolioGuard ??= LocalLivePortfolioExecutionGuard(\n          dailyRiskLimit:\n              _sessionStartEquity! * configuration.dailyLossLimitPercent / 100,\n        );\n      }\n      await _recoverVerifiedQuantaraOrphans(account, openExchangePositions);\n      final sessionId = _sessionId;\n",
)
replace_once(
    service,
    "      final hasUnmanagedExchangeExposure = positions.any(\n        (position) =>\n            position.quantity > 0 &&\n            !managedPositionIds.contains(position.positionId),\n      );\n",
    "      final unmanagedPositions = openExchangePositions\n          .where(\n            (position) =>\n                !managedPositionIds.contains(position.positionId.trim()),\n          )\n          .toList(growable: false);\n      _unmanagedSymbols = List.unmodifiable(\n        unmanagedPositions\n            .map((position) => position.symbol.trim().toUpperCase())\n            .where((symbol) => symbol.isNotEmpty)\n            .toSet()\n            .toList(growable: false)\n          ..sort(),\n      );\n      final hasUnmanagedExchangeExposure = unmanagedPositions.isNotEmpty;\n",
)
replace_once(
    service,
    "        case LocalLiveCycleReadiness.managedExposureHistoryBlocked:\n          _entriesEnabled = false;\n          cycleWarning =\n",
    "        case LocalLiveCycleReadiness.managedExposureHistoryBlocked:\n          _entriesEnabled = false;\n          _entryBlockReason = 'managedExposureHistoryBlocked';\n          cycleWarning =\n",
)
replace_once(
    service,
    "        case LocalLiveCycleReadiness.unmanagedExposureBlocked:\n          _entriesEnabled = false;\n          cycleWarning =\n              'An unmanaged exchange position was detected. New entries are blocked and Quantara did not adopt the position.';\n",
    "        case LocalLiveCycleReadiness.unmanagedExposureBlocked:\n          _entriesEnabled = false;\n          _entryBlockReason = 'unmanagedExchangeExposure';\n          cycleWarning =\n              'An open Bitunix position is not yet owned by this installation. It consumes a portfolio slot; new entries remain blocked while Quantara verifies safe recovery.';\n",
)
# Remove the now-duplicated late session-equity initialization. Portfolio guard
# creation inside the following block is harmless and remains an idempotent fallback.
replace_once(
    service,
    "      _sessionStartEquity ??= account.estimatedEquity;\n      if (_sessionStartEquity != null) {\n        await FlutterForegroundTask.saveData(\n          key: localLiveSessionStartEquityKey,\n          value: _sessionStartEquity!,\n        );\n      }\n      await _reconcileManagedPositions(positions, account.authoritativePnl);\n",
    "      await _reconcileManagedPositions(positions, account.authoritativePnl);\n",
)
replace_once(
    service,
    "          _portfolioBudget = LocalLivePortfolioBudgetStatus(\n            asOf: now,\n            riskLimit: snapshot.dailyRisk.limit,\n            riskConsumed: snapshot.dailyRisk.consumed,\n            riskAvailable: snapshot.dailyRisk.available,\n            openRisk: snapshot.dailyRisk.openRisk,\n            pendingRisk: snapshot.dailyRisk.pendingRisk,\n            ambiguousRisk: snapshot.dailyRisk.ambiguousRisk,\n            reservedMargin: snapshot.margin.reservedMargin,\n            spendableMargin: snapshot.margin.spendable,\n            accountFresh: snapshot.accountFresh,\n            allPositionsProtected: snapshot.allPositionsProtected,\n            liveExecutionAllowed: snapshot.liveExecutionAllowed,\n            blockReason: snapshot.blockReason.name,\n          );\n",
    "          _portfolioBudget = LocalLivePortfolioBudgetStatus(\n            asOf: now,\n            riskLimit: snapshot.dailyRisk.limit,\n            riskConsumed: snapshot.dailyRisk.consumed,\n            riskAvailable: snapshot.dailyRisk.available,\n            openRisk: snapshot.dailyRisk.openRisk,\n            pendingRisk: snapshot.dailyRisk.pendingRisk,\n            ambiguousRisk: snapshot.dailyRisk.ambiguousRisk,\n            reservedMargin: snapshot.margin.reservedMargin,\n            spendableMargin: snapshot.margin.spendable,\n            accountFresh: snapshot.accountFresh,\n            allPositionsProtected: snapshot.allPositionsProtected,\n            liveExecutionAllowed: snapshot.liveExecutionAllowed,\n            blockReason: snapshot.blockReason.name,\n          );\n          if (_unmanagedSymbols.isNotEmpty) {\n            final limit = _portfolioBudget!.riskLimit;\n            _portfolioBudget = LocalLivePortfolioBudgetStatus(\n              asOf: now,\n              riskLimit: limit,\n              riskConsumed: math.max(limit, _portfolioBudget!.riskConsumed),\n              riskAvailable: 0,\n              openRisk: _portfolioBudget!.openRisk,\n              pendingRisk: _portfolioBudget!.pendingRisk,\n              ambiguousRisk: math.max(\n                limit,\n                _portfolioBudget!.ambiguousRisk,\n              ),\n              reservedMargin: _portfolioBudget!.reservedMargin,\n              spendableMargin: 0,\n              accountFresh: _portfolioBudget!.accountFresh,\n              allPositionsProtected: false,\n              liveExecutionAllowed: false,\n              blockReason: 'unmanagedExchangeExposure',\n            );\n          }\n",
)
replace_once(
    service,
    "        } on LocalLiveTradeSafeException catch (error) {\n          _entriesEnabled = false;\n          cycleWarning = error.message;\n",
    "        } on LocalLiveTradeSafeException catch (error) {\n          _entriesEnabled = false;\n          _entryBlockReason = 'portfolioLedgerBlocked';\n          cycleWarning = error.message;\n",
)
replace_once(
    service,
    "      if (lossPercent >= configuration.dailyLossLimitPercent) {\n        _userRequestedEntries = false;\n        _entriesEnabled = false;\n",
    "      if (lossPercent >= configuration.dailyLossLimitPercent) {\n        _userRequestedEntries = false;\n        _entriesEnabled = false;\n        _entryBlockReason = 'dailyLossLimit';\n",
)
replace_once(
    service,
    "      final exchangePositionCount = positions\n          .where((item) => item.quantity > 0)\n          .length;\n      final hasExecutionSlot = LocalLivePortfolioAdmission.hasExecutionSlot(\n        configuredMaximum: configuration.maximumConcurrentPositions,\n        managedPositionCount: _managed.length,\n        exchangePositionCount: exchangePositionCount,\n      );\n",
    "      final exchangePositionCount = _exchangeOpenPositionCount;\n      final hasExecutionSlot = LocalLivePortfolioAdmission.hasExecutionSlot(\n        configuredMaximum: configuration.maximumConcurrentPositions,\n        managedPositionCount: _managed.length,\n        exchangePositionCount: exchangePositionCount,\n      );\n",
)
replace_once(
    service,
    "      } else if (_entriesEnabled && _managed.length != exchangePositionCount) {\n        _auditEvent(\n",
    "      } else if (_entriesEnabled && _managed.length != exchangePositionCount) {\n        _entriesEnabled = false;\n        _entryBlockReason = 'positionOwnershipMismatch';\n        _auditEvent(\n",
)
replace_once(
    service,
    "      await _publish(\n        _entriesEnabled\n            ? LocalLiveTradeState.running\n            : LocalLiveTradeState.managingOnly,\n        cycleWarning ??\n            profitLockWarning ??\n            (_entriesEnabled\n                ? 'Local live scan and exchange reconciliation completed.'\n                : _managed.isEmpty\n                ? 'New entries are paused; no Local Live position is open.'\n                : 'Only exchange-protected positions are being reconciled.'),\n      );\n",
    "      if (profitLockWarning != null) {\n        _entryBlockReason ??= 'protectionReconciliationBlocked';\n      }\n      await _publish(\n        _entriesEnabled\n            ? LocalLiveTradeState.running\n            : LocalLiveTradeState.managingOnly,\n        cycleWarning ??\n            profitLockWarning ??\n            (_entriesEnabled\n                ? 'Local live scan and exchange reconciliation completed.'\n                : _unmanagedSymbols.isNotEmpty\n                ? 'Exchange position recovery is pending; no new entry is allowed.'\n                : _exchangeOpenPositionCount == 0\n                ? 'New entries are paused; no exchange position is open.'\n                : 'Only exchange-protected positions are being reconciled.'),\n      );\n",
)
replace_once(
    service,
    "    } on Object catch (error) {\n      _consecutiveFailures++;\n      _auditEvent('error', _safeError(error));\n",
    "    } on Object catch (error) {\n      _consecutiveFailures++;\n      _entryBlockReason = 'cycleFailure';\n      _auditEvent('error', _safeError(error));\n",
)
replace_once(
    service,
    "      case 'stop':\n        _userRequestedEntries = false;\n        _entriesEnabled = false;\n",
    "      case 'stop':\n        _userRequestedEntries = false;\n        _entriesEnabled = false;\n        _entryBlockReason = null;\n",
)
replace_once(
    service,
    "      case 'block_entries_private_state':\n        _entriesEnabled = false;\n        final reason = message['reason']?.toString() ?? 'unavailable';\n",
    "      case 'block_entries_private_state':\n        _entriesEnabled = false;\n        _entryBlockReason = 'privateAccountState';\n        final reason = message['reason']?.toString() ?? 'unavailable';\n",
)

recovery_method = r'''  Future<void> _recoverVerifiedQuantaraOrphans(
    AutoTradeAccountSnapshot account,
    List<BitunixLivePosition> openPositions,
  ) async {
    final guard = _portfolioGuard;
    final exchange = _exchange;
    final credentials = _credentials;
    if (guard == null || exchange == null || credentials == null) return;

    final ownedIds = _managed
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    for (final position in openPositions) {
      final positionId = position.positionId.trim();
      if (positionId.isEmpty || ownedIds.contains(positionId)) continue;
      final positionPnl = account.authoritativePnl.forPositionId(positionId);
      final entryOrderId = LocalLiveOrphanRecoveryPolicy.uniqueEntryOrderId(
        position: position,
        pnl: positionPnl,
      );
      if (entryOrderId == null) {
        _auditEvent(
          'orphan_recovery_deferred',
          'A unique explicit entry order was not available for secure ownership recovery.',
          symbol: position.symbol,
        );
        continue;
      }
      try {
        final entryOrder = await exchange.fetchOrderDetail(
          orderId: entryOrderId,
          credentials: credentials,
        );
        final rules = await exchange.fetchInstrumentRules(position.symbol);
        final protection = await exchange.fetchPendingProtection(
          credentials,
          symbol: position.symbol,
          positionId: positionId,
        );
        final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
          position: position,
          pnl: positionPnl,
          protection: protection,
          entryOrder: entryOrder,
          rules: rules,
        );
        final managed = decision.managed;
        if (!decision.allowed || managed == null) {
          _auditEvent(
            'orphan_recovery_blocked',
            decision.reason,
            symbol: position.symbol,
          );
          continue;
        }
        final journalRecovered = await _journalObserver
            .recordRecoveredPosition(managed: managed, account: account);
        if (!journalRecovered) {
          _auditEvent(
            'orphan_recovery_deferred',
            'Verified ownership was found, but the durable journal recovery did not commit.',
            symbol: position.symbol,
          );
          continue;
        }
        await guard.adoptVerifiedOpenPosition(
          managed: managed,
          confirmedStop: managed.originalStopLoss,
          now: DateTime.now().toUtc(),
        );
        if (_managed.any((item) => item.positionId == positionId)) continue;
        _managed.add(managed);
        ownedIds.add(positionId);
        _sessionPositionIds.add(positionId);
        _executedSetupIds.add(managed.setupId);
        await _persistState();
        await _persistSessionMetadata();
        _auditEvent(
          'orphan_recovery_completed',
          'A fully protected Quantara position was recovered from verified exchange truth after reinstall.',
          symbol: position.symbol,
        );
      } on LocalLiveTradeSafeException catch (error) {
        _auditEvent(
          'orphan_recovery_blocked',
          error.message,
          symbol: position.symbol,
        );
      } on FormatException catch (error) {
        _auditEvent(
          'orphan_recovery_blocked',
          error.message.toString(),
          symbol: position.symbol,
        );
      }
    }
  }

'''
replace_once(
    service,
    '  Future<void> _reconcilePendingJournalClosures(\n',
    recovery_method + '  Future<void> _reconcilePendingJournalClosures(\n',
)
replace_once(
    service,
    "      openPositionCount: _managed.length,\n      closedPositionCount: _closedPositionCount,\n",
    "      openPositionCount: _exchangeOpenPositionCount,\n      managedPositionCount: _managed.length,\n      unmanagedPositionCount: _unmanagedSymbols.length,\n      unmanagedSymbols: _unmanagedSymbols,\n      entryBlockReason: _entryBlockReason,\n      closedPositionCount: _closedPositionCount,\n",
)

notification_methods = r'''  String _notificationTitle(LocalLiveTradeState state) {
    if (state == LocalLiveTradeState.circuitBreaker) {
      return _notificationCopy(
        'Quantara · توقف ایمنی',
        'Quantara · Circuit breaker',
      );
    }
    if (state == LocalLiveTradeState.starting) {
      return _notificationCopy(
        'Quantara · شروع ترید محلی',
        'Quantara · Starting local live',
      );
    }
    if (state == LocalLiveTradeState.managingOnly) {
      if (_unmanagedSymbols.isNotEmpty) {
        return _notificationCopy(
          'Quantara · بازیابی امن پوزیشن صرافی',
          'Quantara · Secure exchange recovery',
        );
      }
      return _exchangeOpenPositionCount == 0
          ? _notificationCopy(
              'Quantara · ورودهای جدید متوقف',
              'Quantara · Entries paused',
            )
          : _notificationCopy(
              'Quantara · مدیریت پوزیشن محافظت‌شده',
              'Quantara · Managing protected positions',
            );
    }
    return _notificationCopy(
      'Quantara · ترید واقعی محلی',
      'Quantara · Local live canary',
    );
  }

  String _notificationPnlText(LocalLiveTradeState state) {
    if (_unmanagedSymbols.isNotEmpty) {
      final symbols = _unmanagedSymbols.join(', ');
      return _notificationCopy(
        '$_exchangeOpenPositionCount پوزیشن صرافی · بازیابی $symbols در انتظار · ورود مسدود',
        '$_exchangeOpenPositionCount exchange open · $symbols recovery pending · entries blocked',
      );
    }
    if (_exchangeOpenPositionCount == 0) {
      if (state == LocalLiveTradeState.starting || _lastExchangeSync == null) {
        return _notificationCopy(
          'در حال همگام‌سازی حساب Bitunix',
          'Syncing Bitunix account',
        );
      }
      return _entriesEnabled
          ? _notificationCopy(
              'بدون پوزیشن باز · در حال اسکن نمادهای منتخب',
              '0 open · scanning selected symbols',
            )
          : _notificationCopy(
              'بدون پوزیشن باز · ورود جدید متوقف است',
              '0 open · new entries paused',
            );
    }

    final projection = _sessionPnlProjection;
    if (projection == null) {
      return _notificationCopy(
        '$_exchangeOpenPositionCount پوزیشن باز · در حال همگام‌سازی سود و زیان',
        '$_exchangeOpenPositionCount open · syncing exchange PnL',
      );
    }
    final net = projection.accountNetRealized;
    final unrealized = projection.accountUnrealized;
    final pending = _notificationCopy('در انتظار', 'pending');
    final netText = net.isAvailable
        ? '${net.value! >= 0 ? '+' : ''}${net.value!.toStringAsFixed(2)} ${net.currency}'
        : pending;
    final openText = unrealized.isAvailable
        ? '${unrealized.value! >= 0 ? '+' : ''}${unrealized.value!.toStringAsFixed(2)} ${unrealized.currency}'
        : pending;
    return _notificationCopy(
      '$_exchangeOpenPositionCount باز · خالص جلسه $netText · باز $openText',
      '$_exchangeOpenPositionCount open · session net $netText · open $openText',
    );
  }

'''
replace_between(
    service,
    '  String _notificationTitle(LocalLiveTradeState state) {',
    '  String _notificationCopy(String fa, String en) =>',
    notification_methods,
)

print('issue 166 service patch applied')
