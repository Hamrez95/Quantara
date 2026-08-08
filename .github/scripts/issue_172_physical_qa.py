from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace(path: str, old: str, new: str, *, count: int = 1) -> None:
    file = ROOT / path
    text = file.read_text()
    actual = text.count(old)
    if actual < count:
        raise SystemExit(f'{path}: expected at least {count} occurrence(s), found {actual}: {old[:120]!r}')
    text = text.replace(old, new, count)
    file.write_text(text)


# ---------------------------------------------------------------------------
# 1) Preserve open-position time so old unrelated fills cannot be attributed
#    to a newly-open same-symbol position.
# ---------------------------------------------------------------------------
replace(
    'lib/features/auto_trade/domain/trading_pnl_projection.dart',
    """final class ExchangeUnrealizedPnl {\n  const ExchangeUnrealizedPnl({\n    required this.positionId,\n    required this.symbol,\n    required this.value,\n    this.realizedPnl,\n    this.fee,\n    this.funding,\n  });\n\n  final String positionId;\n  final String symbol;\n  final double value;\n  final double? realizedPnl;\n  final double? fee;\n  final double? funding;\n\n  Map<String, Object?> toJson() => {\n    'positionId': positionId,\n    'symbol': symbol,\n    'value': value,\n    'realizedPnl': realizedPnl,\n    'fee': fee,\n    'funding': funding,\n  };\n\n  factory ExchangeUnrealizedPnl.fromJson(Map<String, Object?> json) =>\n      ExchangeUnrealizedPnl(\n        positionId: json['positionId']?.toString() ?? '',\n        symbol: json['symbol']?.toString() ?? '',\n        value: (json['value'] as num?)?.toDouble() ?? 0,\n        realizedPnl: (json['realizedPnl'] as num?)?.toDouble(),\n        fee: (json['fee'] as num?)?.toDouble(),\n        funding: (json['funding'] as num?)?.toDouble(),\n      );\n}\n""",
    """final class ExchangeUnrealizedPnl {\n  const ExchangeUnrealizedPnl({\n    required this.positionId,\n    required this.symbol,\n    required this.value,\n    this.realizedPnl,\n    this.fee,\n    this.funding,\n    this.openedAt,\n  });\n\n  final String positionId;\n  final String symbol;\n  final double value;\n  final double? realizedPnl;\n  final double? fee;\n  final double? funding;\n  final DateTime? openedAt;\n\n  Map<String, Object?> toJson() => {\n    'positionId': positionId,\n    'symbol': symbol,\n    'value': value,\n    'realizedPnl': realizedPnl,\n    'fee': fee,\n    'funding': funding,\n    'openedAt': openedAt?.toUtc().toIso8601String(),\n  };\n\n  factory ExchangeUnrealizedPnl.fromJson(Map<String, Object?> json) =>\n      ExchangeUnrealizedPnl(\n        positionId: json['positionId']?.toString() ?? '',\n        symbol: json['symbol']?.toString() ?? '',\n        value: (json['value'] as num?)?.toDouble() ?? 0,\n        realizedPnl: (json['realizedPnl'] as num?)?.toDouble(),\n        fee: (json['fee'] as num?)?.toDouble(),\n        funding: (json['funding'] as num?)?.toDouble(),\n        openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? '')?.toUtc(),\n      );\n}\n""",
)

# Quarantined historical attribution must remain position-unverified, but only
# ambiguity that could belong to a currently open position may block account
# risk gates.
replace(
    'lib/features/auto_trade/domain/trading_pnl_projection.dart',
    """    final positions = <PositionPnlProjection>[];\n    for (final key in keys) {\n""",
    """    final positions = <PositionPnlProjection>[];\n    final accountBlockingPositionKeys = <String>{};\n    for (final key in keys) {\n""",
)
replace(
    'lib/features/auto_trade/domain/trading_pnl_projection.dart',
    """      final unassignedAttribution = key.startsWith('unassigned-trade:');\n      final positionConflict =\n          unassignedAttribution ||\n          conflicts.any(\n            (item) =>\n                positionFills.any((fill) => fill.tradeId == item) ||\n                item == 'settlement:$key' ||\n                item == 'missing tradeId',\n          );\n""",
    """      final unassignedAttribution = key.startsWith('unassigned-trade:');\n      final attributionCouldAffectOpenPosition =\n          unassignedAttribution &&\n          positionFills.any((fill) {\n            final matchingOpen = unrealizedByPosition.values.where(\n              (candidate) =>\n                  candidate.symbol.trim().toUpperCase() ==\n                  fill.symbol.trim().toUpperCase(),\n            );\n            return matchingOpen.any((candidate) {\n              final openedAt = candidate.openedAt;\n              return openedAt == null ||\n                  !fill.occurredAt.toUtc().isBefore(openedAt.toUtc());\n            });\n          });\n      final identityConflict = conflicts.any(\n        (item) =>\n            positionFills.any((fill) => fill.tradeId == item) ||\n            item == 'settlement:$key' ||\n            item == 'missing tradeId',\n      );\n      final positionConflict = unassignedAttribution || identityConflict;\n""",
)
replace(
    'lib/features/auto_trade/domain/trading_pnl_projection.dart',
    """      final positionVerified = verified && !totalsMismatch;\n      final positionWarning = unassignedAttribution\n""",
    """      final positionVerified = verified && !totalsMismatch;\n      if (identityConflict ||\n          attributionCouldAffectOpenPosition ||\n          totalsMismatch) {\n        accountBlockingPositionKeys.add(key);\n      }\n      final positionWarning = unassignedAttribution\n""",
)
replace(
    'lib/features/auto_trade/domain/trading_pnl_projection.dart',
    """    final componentsVerified =\n        conflicts.isEmpty &&\n        sourceVerified &&\n        positions.every((item) => item.isVerified);\n""",
    """    final componentsVerified =\n        conflicts.isEmpty &&\n        sourceVerified &&\n        accountBlockingPositionKeys.isEmpty;\n""",
)

# Mapper: attribution ambiguity is not source corruption. Keep the unique trade
# in a deterministic quarantine bucket and preserve diagnostics.
replace(
    'lib/features/auto_trade/data/bitunix_pnl_mapper.dart',
    """      if (resolved == null) {\n        final warning =\n            'Trade $tradeId could not be assigned to one exchange position.';\n        if (resolution.ambiguous) {\n          warnings.add(warning);\n        } else {\n          attributionWarnings.add(warning);\n        }\n      }\n""",
    """      if (resolved == null) {\n        attributionWarnings.add(\n          'Trade $tradeId could not be assigned to one exchange position.',\n        );\n      }\n""",
)
replace(
    'lib/features/auto_trade/data/bitunix_pnl_mapper.dart',
    """          positionId:\n              resolved ??\n              (resolution.ambiguous ? '' : '$unassignedPositionPrefix$tradeId'),\n""",
    """          positionId: resolved ?? '$unassignedPositionPrefix$tradeId',\n""",
)
replace(
    'lib/features/auto_trade/data/bitunix_pnl_mapper.dart',
    """    final openMatches = openPositions\n        .where((item) => item.symbol.toUpperCase() == symbol)\n        .map((item) => item.positionId)\n""",
    """    final openMatches = openPositions\n        .where((item) {\n          if (item.symbol.toUpperCase() != symbol) return false;\n          final openedAt = item.openedAt;\n          return openedAt == null || !at.isBefore(openedAt.toUtc());\n        })\n        .map((item) => item.positionId)\n""",
)

# ---------------------------------------------------------------------------
# 2) Faster private sync: parallel independent reads, incremental complete
#    history cache, and open-time propagation. Full history is still fetched
#    whenever the cache cannot prove it covers Bitunix `total` exactly.
# ---------------------------------------------------------------------------
private_path = 'lib/features/auto_trade/data/bitunix_private_api_client.dart'
replace(
    private_path,
    """  final http.Client _client;\n  final DateTime Function() _utcNow;\n  final Random _random;\n""",
    """  final http.Client _client;\n  final DateTime Function() _utcNow;\n  final Random _random;\n  final Map<String, Map<String, Object?>> _positionHistoryCache = {};\n  final Map<String, Map<String, Object?>> _tradeHistoryCache = {};\n""",
)
replace(
    private_path,
    """    final accountResponse = await _signedGet('/api/v1/futures/account', const {\n      'marginCoin': 'USDT',\n    }, credentials);\n    final positionsResponse = await _signedGet(\n      '/api/v1/futures/position/get_pending_positions',\n      const {},\n      credentials,\n    );\n    final ordersResponse = await _signedGet(\n      '/api/v1/futures/trade/get_pending_orders',\n      const {'limit': '100'},\n      credentials,\n    );\n""",
    """    final baseResponses = await Future.wait<Map<String, Object?>>([\n      _signedGet('/api/v1/futures/account', const {\n        'marginCoin': 'USDT',\n      }, credentials),\n      _signedGet(\n        '/api/v1/futures/position/get_pending_positions',\n        const {},\n        credentials,\n      ),\n      _signedGet(\n        '/api/v1/futures/trade/get_pending_orders',\n        const {'limit': '100'},\n        credentials,\n      ),\n    ]);\n    final accountResponse = baseResponses[0];\n    final positionsResponse = baseResponses[1];\n    final ordersResponse = baseResponses[2];\n""",
)
replace(
    private_path,
    """          funding: position.funding,\n        ),\n""",
    """          funding: position.funding,\n          openedAt: position.openedAt,\n        ),\n""",
)

old_history = """    try {\n      final data = await _signedGetCompleteHistory(\n        path: '/api/v1/futures/position/get_history_positions',\n        listKey: 'positionList',\n        identityKey: 'positionId',\n        credentials: credentials,\n      );\n      final parsed = BitunixPnlMapper.settlements(data);\n      settlements = parsed.values;\n      sourceVerified = sourceVerified && parsed.verified;\n      if (parsed.warning != null) pnlWarnings.add(parsed.warning!);\n    } on AutoTradeSafeException catch (error) {\n      settlementsAvailable = false;\n      pnlWarnings.add(error.message);\n    }\n    try {\n      final data = await _signedGetCompleteHistory(\n        path: '/api/v1/futures/trade/get_history_trades',\n        listKey: 'tradeList',\n        identityKey: 'tradeId',\n        credentials: credentials,\n      );\n      final parsed = BitunixPnlMapper.fills(\n        data,\n        openPositions: unrealizedByPosition.values,\n        settlements: settlements,\n      );\n      fills = parsed.values;\n      sourceVerified = sourceVerified && parsed.verified;\n      if (parsed.warning != null) pnlWarnings.add(parsed.warning!);\n    } on AutoTradeSafeException catch (error) {\n      fillsAvailable = false;\n      sourceVerified = false;\n      pnlWarnings.add(error.message);\n    }\n"""
new_history = """    Future<({Map<String, Object?>? data, AutoTradeSafeException? error})>\n    guardedHistory(Future<Map<String, Object?>> Function() request) async {\n      try {\n        return (data: await request(), error: null);\n      } on AutoTradeSafeException catch (error) {\n        return (data: null, error: error);\n      }\n    }\n\n    final historyResults = await Future.wait([\n      guardedHistory(\n        () => _signedGetCachedCompleteHistory(\n          path: '/api/v1/futures/position/get_history_positions',\n          listKey: 'positionList',\n          identityKey: 'positionId',\n          credentials: credentials,\n          cache: _positionHistoryCache,\n        ),\n      ),\n      guardedHistory(\n        () => _signedGetCachedCompleteHistory(\n          path: '/api/v1/futures/trade/get_history_trades',\n          listKey: 'tradeList',\n          identityKey: 'tradeId',\n          credentials: credentials,\n          cache: _tradeHistoryCache,\n        ),\n      ),\n    ]);\n    final settlementResult = historyResults[0];\n    if (settlementResult.error != null) {\n      settlementsAvailable = false;\n      pnlWarnings.add(settlementResult.error!.message);\n    } else {\n      final parsed = BitunixPnlMapper.settlements(settlementResult.data);\n      settlements = parsed.values;\n      sourceVerified = sourceVerified && parsed.verified;\n      if (parsed.warning != null) pnlWarnings.add(parsed.warning!);\n    }\n    final fillResult = historyResults[1];\n    if (fillResult.error != null) {\n      fillsAvailable = false;\n      sourceVerified = false;\n      pnlWarnings.add(fillResult.error!.message);\n    } else {\n      final parsed = BitunixPnlMapper.fills(\n        fillResult.data,\n        openPositions: unrealizedByPosition.values,\n        settlements: settlements,\n      );\n      fills = parsed.values;\n      sourceVerified = sourceVerified && parsed.verified;\n      if (parsed.warning != null) pnlWarnings.add(parsed.warning!);\n    }\n"""
replace(private_path, old_history, new_history)

# Insert incremental cache immediately before the existing complete paginator.
replace(
    private_path,
    """  Future<Map<String, Object?>> _signedGetCompleteHistory({\n""",
    """  Future<Map<String, Object?>> _signedGetCachedCompleteHistory({\n    required String path,\n    required String listKey,\n    required String identityKey,\n    required BitunixApiCredentials credentials,\n    required Map<String, Map<String, Object?>> cache,\n  }) async {\n    Future<Map<String, Object?>> reload() async {\n      final full = await _signedGetCompleteHistory(\n        path: path,\n        listKey: listKey,\n        identityKey: identityKey,\n        credentials: credentials,\n      );\n      final dataRows = _mapList(full[listKey]);\n      cache\n        ..clear()\n        ..addEntries(\n          dataRows.map((row) => MapEntry(_string(row[identityKey]), row)),\n        );\n      return full;\n    }\n\n    if (cache.isEmpty) return reload();\n    final response = await _signedGet(path, {\n      'limit': '$_historyPageSize',\n      'skip': '0',\n    }, credentials);\n    final data = _map(response['data']);\n    if (data == null) return reload();\n    final rows = _mapList(data[listKey]);\n    final total = _optionalInteger(data['total']);\n    if (total == null ||\n        total < 0 ||\n        rows.any((row) => _string(row[identityKey]).isEmpty)) {\n      return reload();\n    }\n    final merged = Map<String, Map<String, Object?>>.of(cache);\n    for (final row in rows) {\n      merged[_string(row[identityKey])] = row;\n    }\n    if (merged.length != total) return reload();\n    cache\n      ..clear()\n      ..addAll(merged);\n    return <String, Object?>{\n      listKey: List.unmodifiable(cache.values),\n      'total': total,\n    };\n  }\n\n  Future<Map<String, Object?>> _signedGetCompleteHistory({\n""",
)

# ---------------------------------------------------------------------------
# 3) Local Live cycle latency: parallel its independent base/history reads and
#    reuse the already-fetched account positions instead of issuing a duplicate
#    pending-position request every cycle.
# ---------------------------------------------------------------------------
local_api = 'lib/features/auto_trade/data/bitunix_local_live_api_client.dart'
replace(
    local_api,
    """    required this.funding,\n  });\n""",
    """    required this.funding,\n    this.openedAt,\n  });\n""",
)
replace(
    local_api,
    """  final double fee;\n  final double funding;\n}\n""",
    """  final double fee;\n  final double funding;\n  final DateTime? openedAt;\n}\n""",
)
replace(
    local_api,
    """    final accountResponse = await _signedGet('/api/v1/futures/account', {\n      'marginCoin': 'USDT',\n    }, credentials);\n    final positions = await fetchPositions(credentials);\n    final ordersResponse = await _signedGet(\n      '/api/v1/futures/trade/get_pending_orders',\n      const {'limit': '100'},\n      credentials,\n    );\n""",
    """    final baseResponses = await Future.wait<Object>([\n      _signedGet('/api/v1/futures/account', {\n        'marginCoin': 'USDT',\n      }, credentials),\n      fetchPositions(credentials),\n      _signedGet(\n        '/api/v1/futures/trade/get_pending_orders',\n        const {'limit': '100'},\n        credentials,\n      ),\n    ]);\n    final accountResponse = baseResponses[0] as Map<String, Object?>;\n    final positions = baseResponses[1] as List<BitunixLivePosition>;\n    final ordersResponse = baseResponses[2] as Map<String, Object?>;\n""",
)
replace(
    local_api,
    """          funding: position.funding,\n        ),\n""",
    """          funding: position.funding,\n          openedAt: position.openedAt,\n        ),\n""",
)
replace(
    local_api,
    """              funding: item.funding,\n            ),\n""",
    """              funding: item.funding,\n              openedAt: item.openedAt,\n            ),\n""",
)
replace(
    local_api,
    """        funding: _number(item['funding']),\n      );\n""",
    """        funding: _number(item['funding']),\n        openedAt: _timestamp(item['ctime']),\n      );\n""",
)
replace(
    local_api,
    """  static int _integer(Object? value, {required int fallback}) {\n""",
    """  static DateTime? _timestamp(Object? value) {\n    final parsed = value is num\n        ? value.toInt()\n        : int.tryParse(value?.toString() ?? '');\n    if (parsed == null || parsed <= 0) return null;\n    return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);\n  }\n\n  static int _integer(Object? value, {required int fallback}) {\n""",
)

service_path = 'lib/features/auto_trade/application/local_live_trade_service.dart'
replace(
    service_path,
    """      final account = await exchange.fetchAccountSnapshot(credentials);\n      final positions = await exchange.fetchPositions(credentials);\n      final openExchangePositions = positions\n""",
    """      final account = await exchange.fetchAccountSnapshot(credentials);\n      final positions = account.positions\n          .map(\n            (position) => BitunixLivePosition(\n              positionId: position.positionId,\n              symbol: position.symbol,\n              quantity: position.quantity.abs(),\n              side: position.side,\n              marginMode: position.marginMode,\n              positionMode: position.positionMode,\n              leverage: position.leverage,\n              averageOpenPrice: position.averageOpenPrice,\n              realizedPnl: position.realizedPnl ?? 0,\n              unrealizedPnl: position.unrealizedPnl,\n              fee: position.fee ?? 0,\n              funding: position.funding ?? 0,\n              openedAt: position.openedAt,\n            ),\n          )\n          .toList(growable: false);\n      final openExchangePositions = positions\n""",
)

# ---------------------------------------------------------------------------
# 4) Cross-channel race: confirm exchange truth with a fresh private snapshot
#    before publishing `divergent`, so a timing skew never hard-blocks entries.
# ---------------------------------------------------------------------------
controller_path = 'lib/features/auto_trade/application/auto_trade_controller.dart'
replace(
    controller_path,
    """  Future<bool> observeLocalLiveOpenPositions({\n    required int openPositionCount,\n    required DateTime observedAt,\n    DateTime? exchangeSyncedAt,\n  }) async {\n    if (_disposed) return false;\n    final effectiveObservedAt = exchangeSyncedAt ?? observedAt;\n    final previousHealth = _reconciliation.health;\n    _reconciliation = _reconciliation.observeLocalLiveOpenPositions(\n      openPositionCount: openPositionCount,\n      observedAt: effectiveObservedAt,\n    );\n    final becameDivergent =\n        _reconciliation.health == PrivateAccountReconciliationHealth.divergent;\n    if (becameDivergent || previousHealth != _reconciliation.health) {\n      notifyListeners();\n    }\n    return reconcile(\n      reason: PrivateAccountRefreshReason.localLiveEvent,\n      force: becameDivergent,\n    );\n  }\n""",
    """  Future<bool> observeLocalLiveOpenPositions({\n    required int openPositionCount,\n    required DateTime observedAt,\n    DateTime? exchangeSyncedAt,\n  }) async {\n    if (_disposed) return false;\n    final effectiveObservedAt = (exchangeSyncedAt ?? observedAt).toUtc();\n    final currentSnapshot = _reconciliation.snapshot;\n    final newerOrEqualObservation =\n        currentSnapshot != null &&\n        !effectiveObservedAt.isBefore(currentSnapshot.syncedAt.toUtc());\n    final countMismatch =\n        currentSnapshot != null &&\n        currentSnapshot.positions.length != openPositionCount;\n\n    if (newerOrEqualObservation && countMismatch) {\n      await reconcile(\n        reason: PrivateAccountRefreshReason.localLiveEvent,\n        force: true,\n      );\n      if (_disposed) return false;\n    }\n\n    final previousHealth = _reconciliation.health;\n    _reconciliation = _reconciliation.observeLocalLiveOpenPositions(\n      openPositionCount: openPositionCount,\n      observedAt: effectiveObservedAt,\n    );\n    if (previousHealth != _reconciliation.health) {\n      notifyListeners();\n    }\n    return !_reconciliation.blocksNewEntries;\n  }\n""",
)

# ---------------------------------------------------------------------------
# 5) Real decision indicators were calculated but dropped by the Professional
#    Strategy Engine. Wire all 23 immutable values into TradeIdea -> Journal.
# ---------------------------------------------------------------------------
strategy_path = 'lib/features/owner_alpha/data/professional_strategy_engine.dart'
replace(
    strategy_path,
    """      context: effectiveContext,\n      fa: fa,\n""",
    """      context: effectiveContext,\n      indicators: indicators,\n      fa: fa,\n""",
)
replace(
    strategy_path,
    """    required AnalysisStrategy strategy,\n    required ProfessionalStrategyContext context,\n    required bool fa,\n""",
    """    required AnalysisStrategy strategy,\n    required ProfessionalStrategyContext context,\n    required TechnicalIndicatorSnapshot indicators,\n    required bool fa,\n""",
)
replace(
    strategy_path,
    """      strategyVersion: '${kind.name}/1.0',\n      marketRegime: setup.regime,\n    );\n  }\n""",
    """      strategyVersion: '${kind.name}/1.0',\n      marketRegime: setup.regime,\n      indicatorSnapshot: _indicatorSnapshot(indicators),\n    );\n  }\n\n  static Map<String, double> _indicatorSnapshot(\n    TechnicalIndicatorSnapshot value,\n  ) => Map.unmodifiable({\n    'ema20': value.ema20,\n    'ema50': value.ema50,\n    'ema200': value.ema200,\n    'ema20SlopeAtr': value.ema20SlopeAtr,\n    'ema50SlopeAtr': value.ema50SlopeAtr,\n    'atr14': value.atr14,\n    'atrPercent': value.atrPercent,\n    'atrExpansionRatio': value.atrExpansionRatio,\n    'rsi14': value.rsi14,\n    'adx14': value.adx14,\n    'plusDi14': value.plusDi14,\n    'minusDi14': value.minusDi14,\n    'relativeVolume20': value.relativeVolume20,\n    'volumeZScore20': value.volumeZScore20,\n    'previousDonchianHigh20': value.previousDonchianHigh20,\n    'previousDonchianLow20': value.previousDonchianLow20,\n    'bollingerMiddle20': value.bollingerMiddle20,\n    'bollingerUpper20': value.bollingerUpper20,\n    'bollingerLower20': value.bollingerLower20,\n    'bollingerBandwidthPercent': value.bollingerBandwidthPercent,\n    'trendEfficiency20': value.trendEfficiency20,\n    'recentSwingHigh': value.recentSwingHigh,\n    'recentSwingLow': value.recentSwingLow,\n  });\n""",
)

# ---------------------------------------------------------------------------
# 6) Center initial market loading in the remaining viewport with a real sliver
#    layout, while preserving the public-data boundary strip and pull-to-refresh.
# ---------------------------------------------------------------------------
page_path = 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace(
    page_path,
    """  @override\n  Widget build(BuildContext context) {\n    final wide = MediaQuery.sizeOf(context).width >= 1024;\n    return RefreshIndicator(\n""",
    """  @override\n  Widget build(BuildContext context) {\n    final wide = MediaQuery.sizeOf(context).width >= 1024;\n    final initialMarketLoading =\n        controller.snapshot == null &&\n        destination != 5 &&\n        destination != 6 &&\n        destination != 7;\n    if (initialMarketLoading) {\n      final horizontal = wide ? 28.0 : 16.0;\n      return RefreshIndicator(\n        onRefresh: onRefresh,\n        child: CustomScrollView(\n          key: PageStorageKey('owner-alpha-$destination'),\n          physics: const AlwaysScrollableScrollPhysics(),\n          slivers: [\n            SliverPadding(\n              padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 0),\n              sliver: SliverToBoxAdapter(\n                child: Center(\n                  child: ConstrainedBox(\n                    constraints: const BoxConstraints(maxWidth: 1280),\n                    child: Column(\n                      crossAxisAlignment: CrossAxisAlignment.stretch,\n                      children: [\n                        if (showTopBar) ...[\n                          _AlphaTopBar(\n                            controller: controller,\n                            themeMode: themeMode,\n                            onToggleTheme: onToggleTheme,\n                          ),\n                          const SizedBox(height: 14),\n                        ],\n                        _LiveBoundaryStrip(realtimeMonitor: realtimeMonitor),\n                        if (controller.error != null) ...[\n                          const SizedBox(height: 12),\n                          _AlphaErrorStrip(\n                            message: controller.error!,\n                            stale: controller.hasStaleSnapshot,\n                            onRetry: controller.refresh,\n                          ),\n                        ],\n                      ],\n                    ),\n                  ),\n                ),\n              ),\n            ),\n            SliverFillRemaining(\n              hasScrollBody: false,\n              child: Padding(\n                padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 32),\n                child: Center(\n                  child: ConstrainedBox(\n                    constraints: const BoxConstraints(maxWidth: 720),\n                    child: _InitialLoading(controller: controller),\n                  ),\n                ),\n              ),\n            ),\n          ],\n        ),\n      );\n    }\n    return RefreshIndicator(\n""",
)

# ---------------------------------------------------------------------------
# Regression updates + dedicated Issue #172 tests.
# ---------------------------------------------------------------------------
mapper_test = ROOT / 'test/bitunix_pnl_mapper_physical_canary_test.dart'
text = mapper_test.read_text()
text = text.replace(
    """    expect(fills.verified, isFalse);\n    expect(fills.values.single.positionId, isEmpty);\n    expect(fills.warning, contains('could not be assigned'));\n""",
    """    expect(fills.verified, isTrue);\n    expect(\n      fills.values.single.positionId,\n      'unassigned-trade:ambiguous',\n    );\n    expect(fills.warning, contains('could not be assigned'));\n""",
)
mapper_test.write_text(text)

issue_test = ROOT / 'test/issue_172_physical_qa_regression_test.dart'
issue_test.write_text(r'''import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/application/auto_trade_controller.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_pnl_mapper.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/data/secure_auto_trade_credentials_store.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  test('old unattributed GRAM trade stays diagnostic but does not block open BNB', () {
    final bnbOpenedAt = DateTime.utc(2026, 8, 8, 10);
    final oldTradeAt = DateTime.utc(2026, 8, 5, 3, 19, 14);
    final open = <ExchangeUnrealizedPnl>[
      ExchangeUnrealizedPnl(
        positionId: 'bnb-open',
        symbol: 'BNBUSDT',
        value: -0.0228,
        realizedPnl: 0,
        fee: 0,
        funding: 0,
        openedAt: bnbOpenedAt,
      ),
    ];
    final fills = BitunixPnlMapper.fills(
      {
        'tradeList': [
          {
            'tradeId': '2795413522294203930',
            'orderId': '7352379888826528074',
            'symbol': 'GRAMUSDT',
            'qty': '42.9',
            'price': '1.389',
            'realizedPNL': '-0.2574',
            'fee': '0.03575286',
            'ctime': oldTradeAt.millisecondsSinceEpoch,
            'reduceOnly': true,
            'side': 'SELL',
          },
        ],
      },
      openPositions: open,
      settlements: const [],
    );

    expect(fills.verified, isTrue);
    expect(fills.warning, contains('could not be assigned'));
    expect(
      fills.values.single.positionId,
      'unassigned-trade:2795413522294203930',
    );

    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: DateTime.utc(2026, 8, 8, 10, 5),
      unrealizedByPosition: {open.single.positionId: open.single},
      fills: fills.values,
      settlements: const [],
      sourceVerified: fills.verified,
    );

    expect(projection.isVerified, isTrue);
    expect(projection.isReadyForRiskGates, isTrue);
    expect(projection.forPositionId('bnb-open')?.isVerified, isTrue);
    final quarantined = projection.positions.singleWhere(
      (item) => item.positionId.startsWith('unassigned-trade:'),
    );
    expect(quarantined.isVerified, isFalse);
    expect(quarantined.warning, contains('quarantined'));
  });

  test('unattributed fill that could belong to an active same-symbol position blocks', () {
    final openedAt = DateTime.utc(2026, 8, 8, 10);
    final tradeAt = openedAt.add(const Duration(minutes: 5));
    final open = <ExchangeUnrealizedPnl>[
      ExchangeUnrealizedPnl(
        positionId: 'bnb-a',
        symbol: 'BNBUSDT',
        value: 0,
        realizedPnl: 0,
        fee: 0,
        funding: 0,
        openedAt: openedAt,
      ),
      ExchangeUnrealizedPnl(
        positionId: 'bnb-b',
        symbol: 'BNBUSDT',
        value: 0,
        realizedPnl: 0,
        fee: 0,
        funding: 0,
        openedAt: openedAt,
      ),
    ];
    final fills = BitunixPnlMapper.fills(
      {
        'tradeList': [
          {
            'tradeId': 'active-ambiguous',
            'orderId': 'active-order',
            'symbol': 'BNBUSDT',
            'qty': '0.01',
            'price': '596.2',
            'realizedPNL': '0',
            'fee': '0.001',
            'ctime': tradeAt.millisecondsSinceEpoch,
            'reduceOnly': false,
            'side': 'BUY',
          },
        ],
      },
      openPositions: open,
      settlements: const [],
    );
    expect(fills.verified, isTrue);
    expect(fills.values.single.positionId, 'unassigned-trade:active-ambiguous');

    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: tradeAt.add(const Duration(seconds: 1)),
      unrealizedByPosition: {for (final item in open) item.positionId: item},
      fills: fills.values,
      settlements: const [],
      sourceVerified: fills.verified,
    );
    expect(projection.isVerified, isFalse);
    expect(projection.isReadyForRiskGates, isFalse);
  });

  test('Local Live mismatch is confirmed before listeners can see divergent state', () async {
    var pendingPositionReads = 0;
    final now = DateTime.utc(2026, 8, 8, 12);
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/futures/position/get_pending_positions') {
        pendingPositionReads += 1;
      }
      return _response(
        request.url.path,
        includeOpenPosition: pendingPositionReads <= 1,
      );
    });
    final controller = AutoTradeController(
      apiClient: BitunixPrivateApiClient(client: client, utcNow: () => now),
      credentialsStore: _MemoryCredentialsStore(_credentials),
      utcNow: () => now,
    );
    final observedHealth = <PrivateAccountReconciliationHealth>[];
    controller.addListener(() => observedHealth.add(controller.reconciliation.health));
    addTearDown(() {
      controller.dispose();
      client.close();
    });

    await controller.initialize();
    observedHealth.clear();
    final ok = await controller.observeLocalLiveOpenPositions(
      openPositionCount: 0,
      observedAt: now.add(const Duration(seconds: 5)),
      exchangeSyncedAt: now.add(const Duration(seconds: 5)),
    );

    expect(ok, isTrue);
    expect(controller.snapshot?.positions, isEmpty);
    expect(controller.reconciliation.health, PrivateAccountReconciliationHealth.fresh);
    expect(observedHealth, isNot(contains(PrivateAccountReconciliationHealth.divergent)));
  });

  test('persistent Local Live mismatch still fails closed after confirmation', () async {
    final now = DateTime.utc(2026, 8, 8, 12);
    final client = MockClient(
      (request) async => _response(request.url.path, includeOpenPosition: true),
    );
    final controller = AutoTradeController(
      apiClient: BitunixPrivateApiClient(client: client, utcNow: () => now),
      credentialsStore: _MemoryCredentialsStore(_credentials),
      utcNow: () => now,
    );
    addTearDown(() {
      controller.dispose();
      client.close();
    });

    await controller.initialize();
    final ok = await controller.observeLocalLiveOpenPositions(
      openPositionCount: 0,
      observedAt: now.add(const Duration(seconds: 5)),
      exchangeSyncedAt: now.add(const Duration(seconds: 5)),
    );

    expect(ok, isFalse);
    expect(controller.reconciliation.health, PrivateAccountReconciliationHealth.divergent);
    expect(controller.reconciliation.blocksNewEntries, isTrue);
    expect(controller.canManageExistingPosition, isTrue);
  });

  test('dispose during delayed connect completion does not throw or notify afterward', () async {
    final gate = Completer<void>();
    final client = MockClient((request) async {
      await gate.future;
      return _response(request.url.path, includeOpenPosition: false);
    });
    final controller = AutoTradeController(
      apiClient: BitunixPrivateApiClient(client: client),
      credentialsStore: _MemoryCredentialsStore(null),
    );
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    final operation = controller.connect(
      apiKey: _credentials.apiKey,
      secretKey: _credentials.secretKey,
    );
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    final beforeRelease = notifications;
    gate.complete();
    await operation;
    expect(notifications, beforeRelease);
    client.close();
  });

  test('source keeps fast sync, centered loader and real indicator wiring', () {
    final privateSource = File(
      'lib/features/auto_trade/data/bitunix_private_api_client.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    final strategySource = File(
      'lib/features/owner_alpha/data/professional_strategy_engine.dart',
    ).readAsStringSync();
    final serviceSource = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(privateSource, contains('Future.wait<Map<String, Object?>>'));
    expect(privateSource, contains('_signedGetCachedCompleteHistory'));
    expect(privateSource, contains("merged.length != total"));
    expect(pageSource, contains('SliverFillRemaining('));
    expect(pageSource, contains('hasScrollBody: false'));
    expect(strategySource, contains('indicatorSnapshot: _indicatorSnapshot(indicators)'));
    for (final key in const [
      'ema20',
      'ema50',
      'ema200',
      'atr14',
      'rsi14',
      'adx14',
      'plusDi14',
      'minusDi14',
      'relativeVolume20',
      'volumeZScore20',
      'trendEfficiency20',
      'recentSwingHigh',
      'recentSwingLow',
    ]) {
      expect(strategySource, contains("'$key': value.$key"));
    }
    expect(
      serviceSource,
      isNot(contains(
        'final account = await exchange.fetchAccountSnapshot(credentials);\n      final positions = await exchange.fetchPositions(credentials);',
      )),
    );
  });
}

const _credentials = BitunixApiCredentials(
  apiKey: 'test-api-key-123',
  secretKey: 'test-secret-key-123',
);

http.Response _response(String path, {required bool includeOpenPosition}) {
  final Object data = switch (path) {
    '/api/v1/futures/account' => {
      'marginCoin': 'USDT',
      'available': '29.0',
      'frozen': '0',
      'margin': includeOpenPosition ? '2.4' : '0',
      'crossUnrealizedPNL': '0',
      'isolationUnrealizedPNL': includeOpenPosition ? '-0.02' : '0',
      'positionMode': 'HEDGE',
    },
    '/api/v1/futures/position/get_pending_positions' => includeOpenPosition
        ? [
            {
              'positionId': 'bnb-position',
              'symbol': 'BNBUSDT',
              'qty': '0.04',
              'side': 'LONG',
              'marginMode': 'ISOLATION',
              'positionMode': 'HEDGE',
              'leverage': '10',
              'margin': '2.4',
              'unrealizedPNL': '-0.02',
              'liqPrice': '500',
              'avgOpenPrice': '596.26',
              'ctime': DateTime.utc(2026, 8, 8, 10).millisecondsSinceEpoch,
            },
          ]
        : <Object>[],
    '/api/v1/futures/trade/get_pending_orders' => {'orderList': <Object>[]},
    '/api/v1/futures/tpsl/get_pending_orders' => {'orderList': <Object>[]},
    '/api/v1/futures/position/get_history_positions' => {
      'positionList': <Object>[],
      'total': 0,
    },
    '/api/v1/futures/trade/get_history_trades' => {
      'tradeList': <Object>[],
      'total': 0,
    },
    _ => throw StateError('Unexpected Bitunix path: $path'),
  };
  return http.Response(jsonEncode({'code': 0, 'data': data}), 200);
}

final class _MemoryCredentialsStore implements AutoTradeCredentialsStore {
  _MemoryCredentialsStore(this.value);

  BitunixApiCredentials? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<BitunixApiCredentials?> load() async => value;

  @override
  Future<void> save(BitunixApiCredentials credentials) async {
    value = credentials;
  }
}
''')

print('Issue #172 patch applied.')
