from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'missing patch target in {path}: {old[:80]!r}')
    path.write_text(text.replace(old, new, 1))


api = ROOT / 'lib/features/auto_trade/data/bitunix_local_live_api_client.dart'
api_text = api.read_text()
marker = '  Future<AutoTradeAccountSnapshot> fetchAccountSnapshot(\n'
if 'fetchCurrentAccountSnapshot(' not in api_text:
    method = r'''  /// Bounded current-state REST verification for the private WebSocket Hot Path.
  /// Historical fills/settlements intentionally stay out of this method.
  Future<AutoTradeAccountSnapshot> fetchCurrentAccountSnapshot(
    BitunixApiCredentials credentials,
  ) async {
    final responses = await Future.wait<Object>([
      _signedGet('/api/v1/futures/account', {
        'marginCoin': 'USDT',
      }, credentials),
      fetchPositions(credentials),
      _signedGet('/api/v1/futures/trade/get_pending_orders', const {
        'limit': '100',
      }, credentials),
      fetchPendingProtection(credentials),
    ]);
    final accountResponse = responses[0] as Map<String, Object?>;
    final positions = responses[1] as List<BitunixLivePosition>;
    final ordersResponse = responses[2] as Map<String, Object?>;
    final protections = responses[3] as List<BitunixPendingProtection>;
    final account = _firstMap(accountResponse['data']);
    if (account == null) {
      throw const LocalLiveTradeSafeException(
        'Bitunix current account data was empty or malformed.',
      );
    }
    final orderData = ordersResponse['data'];
    final orderMaps = orderData is Map<String, Object?>
        ? _mapList(orderData['orderList'])
        : const <Map<String, Object?>>[];
    final asOf = _utcNow().toUtc();
    final protectionOrders = protections
        .map(
          (item) => AutoTradeProtectionOrder(
            exchangeId: item.orderId,
            positionId: item.positionId,
            symbol: item.symbol,
            takeProfitPrice:
                item.takeProfitPrice > 0 ? item.takeProfitPrice : null,
            takeProfitQuantity:
                item.takeProfitQuantity > 0 ? item.takeProfitQuantity : null,
            stopLossPrice: item.stopLossPrice > 0 ? item.stopLossPrice : null,
            stopLossQuantity:
                item.stopLossQuantity > 0 ? item.stopLossQuantity : null,
          ),
        )
        .toList(growable: false);
    return AutoTradeAccountSnapshot(
      marginCoin: _string(account['marginCoin'], fallback: 'USDT'),
      available: _number(account['available']),
      frozen: _number(account['frozen']),
      positionMargin: _number(account['margin']),
      crossUnrealizedPnl: _number(account['crossUnrealizedPNL']),
      isolatedUnrealizedPnl: _number(account['isolationUnrealizedPNL']),
      positionMode: _string(account['positionMode'], fallback: 'UNKNOWN'),
      positions: positions
          .map(
            (item) => AutoTradePosition(
              positionId: item.positionId,
              symbol: item.symbol,
              quantity: item.quantity,
              side: item.side,
              marginMode: item.marginMode,
              positionMode: item.positionMode,
              leverage: item.leverage,
              margin: 0,
              unrealizedPnl: item.unrealizedPnl,
              liquidationPrice: 0,
              averageOpenPrice: item.averageOpenPrice,
              realizedPnl: item.realizedPnl,
              fee: item.fee,
              funding: item.funding,
              openedAt: item.openedAt,
            ),
          )
          .toList(growable: false),
      orders: orderMaps.map(_orderFromJson).toList(growable: false),
      protectionOrders: protectionOrders,
      protectionVerifications: {
        for (final position in positions)
          position.positionId: AutoTradeProtectionVerification.verified(
            asOf: asOf,
          ),
      },
      syncedAt: asOf,
    );
  }

'''
    if marker not in api_text:
        raise SystemExit('fetchAccountSnapshot marker not found')
    api.write_text(api_text.replace(marker, method + marker, 1))

service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
replace_once(
    service,
    "import '../data/bitunix_local_live_api_client.dart';\n",
    "import '../data/bitunix_local_live_api_client.dart';\nimport '../data/bitunix_private_websocket_client.dart';\n",
)
replace_once(
    service,
    "import 'profit_lock_promotion_executor.dart';\n",
    "import 'private_truth_account_snapshot.dart';\nimport 'private_truth_coordinator.dart';\nimport 'profit_lock_promotion_executor.dart';\n",
)
replace_once(
    service,
    "  LocalLivePortfolioExecutionGuard? _portfolioGuard;\n",
    "  LocalLivePortfolioExecutionGuard? _portfolioGuard;\n  PrivateTruthCoordinator? _privateTruth;\n  http.Client? _coldHttpClient;\n  BitunixLocalLiveApiClient? _coldExchange;\n  TradingPnlProjection? _coldPnlProjection;\n  bool _coldPnlRefreshRunning = false;\n  DateTime? _lastColdPnlRefresh;\n",
)
replace_once(
    service,
    "    _destroyed = true;\n    _httpClient?.close();\n    _httpClient = null;\n    _exchange = null;\n    _credentials = null;\n",
    "    _destroyed = true;\n    await _privateTruth?.dispose();\n    _privateTruth = null;\n    _httpClient?.close();\n    _httpClient = null;\n    _exchange = null;\n    _coldHttpClient?.close();\n    _coldHttpClient = null;\n    _coldExchange = null;\n    _credentials = null;\n",
)
replace_once(
    service,
    "        _httpClient?.close();\n        _httpClient = http.Client();\n        _exchange = BitunixLocalLiveApiClient(client: _httpClient!);\n        _userRequestedEntries = message['entriesEnabled'] == true;\n",
    "        _httpClient?.close();\n        _httpClient = http.Client();\n        _exchange = BitunixLocalLiveApiClient(client: _httpClient!);\n        _coldHttpClient?.close();\n        _coldHttpClient = http.Client();\n        _coldExchange = BitunixLocalLiveApiClient(client: _coldHttpClient!);\n        await _privateTruth?.dispose();\n        final privateTruth = PrivateTruthCoordinator(\n          BitunixPrivateWebSocketClient(),\n          (value) => _exchange!.fetchCurrentAccountSnapshot(value),\n        );\n        _privateTruth = privateTruth;\n        await privateTruth.start(_credentials!);\n        unawaited(_refreshColdPnl());\n        _userRequestedEntries = message['entriesEnabled'] == true;\n",
)
replace_once(
    service,
    "      final account = await exchange.fetchAccountSnapshot(credentials);\n      final positions = account.positions\n",
    "      final privateTruth = _privateTruth;\n      final restBaseline = privateTruth?.latestRestSnapshot;\n      if (privateTruth == null || restBaseline == null) {\n        _entriesEnabled = false;\n        _entryBlockReason = 'privateAccountState';\n        await _publish(\n          LocalLiveTradeState.managingOnly,\n          'Private WebSocket truth is waiting for bounded REST verification. New entries remain blocked.',\n        );\n        return;\n      }\n      _scheduleColdPnlRefresh();\n      final hotAccount = PrivateTruthAccountSnapshotBuilder.build(\n        projection: privateTruth.current,\n        restBaseline: restBaseline,\n        coldPnlProjection: _coldPnlProjection,\n      );\n      final account = hotAccount.snapshot;\n      final positions = account.positions\n",
)
replace_once(
    service,
    "      _exchangeOpenPositionCount = openExchangePositions.length;\n      _lastExchangeSync = DateTime.now().toUtc();\n      _entriesEnabled =\n          LocalLiveManagementOnlyAfterFlatPolicy.effectiveEntriesEnabled(\n            userRequestedEntries: _userRequestedEntries,\n            managementOnlyAfterFlat: _managementOnlyAfterFlat,\n          );\n      _entryBlockReason = _managementOnlyAfterFlat\n          ? 'managementOnlyAfterFlat'\n          : null;\n",
    "      _exchangeOpenPositionCount = openExchangePositions.length;\n      _lastExchangeSync = privateTruth.current.updatedAtUtc;\n      final privateTruthReady =\n          privateTruth.canAdmitNewEntries && hotAccount.completeForNewEntry;\n      _entriesEnabled =\n          LocalLiveManagementOnlyAfterFlatPolicy.effectiveEntriesEnabled(\n            userRequestedEntries: _userRequestedEntries,\n            managementOnlyAfterFlat: _managementOnlyAfterFlat,\n          ) &&\n          privateTruthReady;\n      _entryBlockReason = _managementOnlyAfterFlat\n          ? 'managementOnlyAfterFlat'\n          : privateTruthReady\n          ? null\n          : 'privateAccountState:${privateTruth.current.lagReason.name}';\n",
)
restore_marker = '  Future<void> _restoreNonSecretState() async {\n'
service_text = service.read_text()
if '_refreshColdPnl() async {' not in service_text:
    cold_methods = r'''  void _scheduleColdPnlRefresh() {
    final last = _lastColdPnlRefresh;
    if (_coldPnlRefreshRunning ||
        (last != null &&
            DateTime.now().toUtc().difference(last) <
                const Duration(minutes: 5))) {
      return;
    }
    unawaited(_refreshColdPnl());
  }

  Future<void> _refreshColdPnl() async {
    if (_coldPnlRefreshRunning) return;
    final exchange = _coldExchange;
    final credentials = _credentials;
    if (exchange == null || credentials == null) return;
    _coldPnlRefreshRunning = true;
    try {
      final snapshot = await exchange.fetchAccountSnapshot(credentials);
      _coldPnlProjection = snapshot.authoritativePnl;
      _lastColdPnlRefresh = DateTime.now().toUtc();
    } on Object catch (error) {
      _auditEvent('cold_pnl_refresh_deferred', _safeError(error));
    } finally {
      _coldPnlRefreshRunning = false;
    }
  }

'''
    if restore_marker not in service_text:
        raise SystemExit('restore marker not found')
    service.write_text(service_text.replace(restore_marker, cold_methods + restore_marker, 1))
