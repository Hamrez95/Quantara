from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'missing target in {path}: {old[:100]!r}')
    path.write_text(text.replace(old, new, 1))


client = ROOT / 'lib/features/auto_trade/data/bitunix_private_websocket_client.dart'
replace_once(
    client,
    '  bool get isRunning;\n\n  Future<void> start',
    '  bool get isRunning;\n  int get droppedOrMalformedEvents;\n\n  Future<void> start',
)
replace_once(
    client,
    '  int _reconnectAttempt = 0;\n',
    '  int _reconnectAttempt = 0;\n  int _droppedOrMalformedEvents = 0;\n',
)
replace_once(
    client,
    '  bool get isRunning => _running;\n\n  @override\n  Future<void> start',
    '  bool get isRunning => _running;\n  @override\n  int get droppedOrMalformedEvents => _droppedOrMalformedEvents;\n\n  @override\n  Future<void> start',
)
replace_once(
    client,
    '    final decoded = _decode(raw);\n    if (decoded is! Map<String, Object?>) return;\n',
    '    final decoded = _decode(raw);\n    if (decoded is! Map<String, Object?>) {\n      _droppedOrMalformedEvents++;\n      return;\n    }\n',
)
replace_once(
    client,
    '    if (event != null && !_events.isClosed) _events.add(event);\n',
    '    if (event != null && !_events.isClosed) {\n      _events.add(event);\n    } else if (event == null) {\n      _droppedOrMalformedEvents++;\n    }\n',
)

coordinator = ROOT / 'lib/features/auto_trade/application/private_truth_coordinator.dart'
replace_once(
    coordinator,
    "import 'private_truth_reconciler.dart';\n",
    "import 'private_truth_reconciler.dart';\nimport 'private_truth_telemetry.dart';\n",
)
replace_once(
    coordinator,
    '    this.maximumRestVerificationAge = const Duration(seconds: 90),\n',
    '    this.maximumRestVerificationAge = const Duration(seconds: 90),\n    this.restRequestsPerVerification = 4,\n',
)
replace_once(
    coordinator,
    '  final Duration maximumRestVerificationAge;\n',
    '  final Duration maximumRestVerificationAge;\n  final int restRequestsPerVerification;\n  final PrivateTruthTelemetryCollector _telemetry =\n      PrivateTruthTelemetryCollector();\n',
)
replace_once(
    coordinator,
    '  bool get isRunning => _running;\n\n  bool get canAdmitNewEntries',
    '''  bool get isRunning => _running;\n\n  PrivateTruthTelemetrySnapshot telemetrySnapshot([DateTime? nowUtc]) =>\n      _telemetry.snapshot(\n        projection: _projection,\n        droppedOrMalformedEvents: _socketClient.droppedOrMalformedEvents,\n        nowUtc: (nowUtc ?? _clock()).toUtc(),\n      );\n\n  void recordSupervisorPublish(DateTime publishedAtUtc) {\n    _telemetry.recordSupervisorPublish(\n      projectionUpdatedAtUtc: _projection.updatedAtUtc,\n      publishedAtUtc: publishedAtUtc,\n    );\n  }\n\n  void recordRestRequests(int count, [DateTime? atUtc]) {\n    _telemetry.recordRestRequests(count, (atUtc ?? _clock()).toUtc());\n  }\n\n  bool get canAdmitNewEntries''',
)
replace_once(
    coordinator,
    '  void _onEvent(PrivateTruthEvent event) {\n    if (!_running) return;\n',
    '  void _onEvent(PrivateTruthEvent event) {\n    if (!_running) return;\n    _telemetry.recordEvent(event);\n',
)
replace_once(
    coordinator,
    '      case PrivateWsClientState.reconnecting:\n        _socketActive = false;\n',
    '      case PrivateWsClientState.reconnecting:\n        _socketActive = false;\n        _telemetry.recordReconnect(status.atUtc);\n',
)
replace_once(
    coordinator,
    '    _verifying = true;\n    final generation = ++_verificationGeneration;\n',
    '    _verifying = true;\n    final generation = ++_verificationGeneration;\n    recordRestRequests(restRequestsPerVerification);\n',
)
replace_once(
    coordinator,
    '      _latestRestSnapshot = snapshot;\n      _setProjection(\n',
    '      _latestRestSnapshot = snapshot;\n      _telemetry.recordReconciled(_clock().toUtc());\n      _setProjection(\n',
)
replace_once(
    coordinator,
    '  void _setProjection(PrivateTruthProjection next) {\n    _projection = next;\n',
    '  void _setProjection(PrivateTruthProjection next) {\n    _projection = next;\n    _telemetry.recordEntryGate(\n      canAdmit: canAdmitNewEntries,\n      atUtc: _clock().toUtc(),\n    );\n',
)

status = ROOT / 'lib/features/auto_trade/domain/local_live_trade_models.dart'
replace_once(
    status,
    '    this.entryBlockReason,\n    this.closedPositionCount = 0,\n',
    '''    this.entryBlockReason,\n    this.privateTruthHealth,\n    this.privateTruthLagReason,\n    this.privateTruthAgeMs,\n    this.privateTruthRestVerificationAgeMs,\n    this.privateTruthTelemetry,\n    this.closedPositionCount = 0,\n''',
)
replace_once(
    status,
    '  final String? entryBlockReason;\n  final int closedPositionCount;\n',
    '''  final String? entryBlockReason;\n  final String? privateTruthHealth;\n  final String? privateTruthLagReason;\n  final int? privateTruthAgeMs;\n  final int? privateTruthRestVerificationAgeMs;\n  final Map<String, Object?>? privateTruthTelemetry;\n  final int closedPositionCount;\n''',
)
replace_once(
    status,
    "    'entryBlockReason': entryBlockReason,\n    'closedPositionCount': closedPositionCount,\n",
    '''    'entryBlockReason': entryBlockReason,\n    'privateTruthHealth': privateTruthHealth,\n    'privateTruthLagReason': privateTruthLagReason,\n    'privateTruthAgeMs': privateTruthAgeMs,\n    'privateTruthRestVerificationAgeMs': privateTruthRestVerificationAgeMs,\n    'privateTruthTelemetry': privateTruthTelemetry,\n    'closedPositionCount': closedPositionCount,\n''',
)
replace_once(
    status,
    "    entryBlockReason: json['entryBlockReason']?.toString(),\n    closedPositionCount:",
    '''    entryBlockReason: json['entryBlockReason']?.toString(),\n    privateTruthHealth: json['privateTruthHealth']?.toString(),\n    privateTruthLagReason: json['privateTruthLagReason']?.toString(),\n    privateTruthAgeMs: (json['privateTruthAgeMs'] as num?)?.toInt(),\n    privateTruthRestVerificationAgeMs:\n        (json['privateTruthRestVerificationAgeMs'] as num?)?.toInt(),\n    privateTruthTelemetry: _stringObjectMap(json['privateTruthTelemetry']),\n    closedPositionCount:''',
)
helper_marker = 'LocalLivePortfolioBudgetStatus? _portfolioBudgetFromJson(Object? value) {\n'
status_text = status.read_text()
if '_stringObjectMap(Object? value)' not in status_text:
    helper = '''Map<String, Object?>? _stringObjectMap(Object? value) {\n  if (value is Map<String, Object?>) return Map.unmodifiable(value);\n  if (value is Map<Object?, Object?>) {\n    return Map.unmodifiable(\n      value.map((key, item) => MapEntry(key.toString(), item)),\n    );\n  }\n  return null;\n}\n\n'''
    if helper_marker not in status_text:
        raise SystemExit('status helper marker missing')
    status.write_text(status_text.replace(helper_marker, helper + helper_marker, 1))

service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
replace_once(
    service,
    '    final status = LocalLiveTradeStatus(\n      state: state,\n      updatedAt: DateTime.now().toUtc(),\n',
    '''    final publishAt = DateTime.now().toUtc();\n    final privateTruth = _privateTruth;\n    privateTruth?.recordSupervisorPublish(publishAt);\n    final privateProjection = privateTruth?.current;\n    final privateTelemetry = privateTruth?.telemetrySnapshot(publishAt);\n    final restVerifiedAt = privateProjection?.restVerifiedAtUtc;\n    final status = LocalLiveTradeStatus(\n      state: state,\n      updatedAt: publishAt,\n''',
)
replace_once(
    service,
    '      entryBlockReason: _entryBlockReason,\n      closedPositionCount: _closedPositionCount,\n',
    '''      entryBlockReason: _entryBlockReason,\n      privateTruthHealth: privateProjection?.health.name,\n      privateTruthLagReason: privateProjection?.lagReason.name,\n      privateTruthAgeMs: privateProjection == null\n          ? null\n          : publishAt\n                .difference(privateProjection.updatedAtUtc)\n                .inMilliseconds\n                .clamp(0, 1 << 31),\n      privateTruthRestVerificationAgeMs: restVerifiedAt == null\n          ? null\n          : publishAt.difference(restVerifiedAt).inMilliseconds.clamp(0, 1 << 31),\n      privateTruthTelemetry: privateTelemetry?.toJson(),\n      closedPositionCount: _closedPositionCount,\n''',
)
replace_once(
    service,
    '    final values = await Future.wait<Object>([\n      exchange.fetchOrderDetail',
    '    _privateTruth?.recordRestRequests(2);\n    final values = await Future.wait<Object>([\n      exchange.fetchOrderDetail',
)
