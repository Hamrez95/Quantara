import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ManualTradeExecutionState { submitting, ambiguous, protected, failedSafe }

final class ManualTradeExecutionRecord {
  const ManualTradeExecutionRecord({
    required this.setupId,
    required this.symbol,
    required this.clientId,
    required this.state,
    required this.updatedAtUtc,
    required this.margin,
    required this.leverage,
    required this.targetCount,
    this.systemMargin,
    this.systemLeverage,
    this.systemTargetCount,
    this.entryOrderId,
    this.positionId,
    this.stopOrderId,
    this.targetOrderIds = const [],
    this.message,
  });

  final String setupId;
  final String symbol;
  final String clientId;
  final ManualTradeExecutionState state;
  final DateTime updatedAtUtc;
  final double margin;
  final int leverage;
  final int targetCount;
  final double? systemMargin;
  final int? systemLeverage;
  final int? systemTargetCount;
  final String? entryOrderId;
  final String? positionId;
  final String? stopOrderId;
  final List<String> targetOrderIds;
  final String? message;

  bool get blocksDuplicateSubmission =>
      state == ManualTradeExecutionState.submitting ||
      state == ManualTradeExecutionState.ambiguous ||
      state == ManualTradeExecutionState.protected;

  ManualTradeExecutionRecord copyWith({
    ManualTradeExecutionState? state,
    DateTime? updatedAtUtc,
    String? entryOrderId,
    String? positionId,
    String? stopOrderId,
    List<String>? targetOrderIds,
    String? message,
  }) => ManualTradeExecutionRecord(
    setupId: setupId,
    symbol: symbol,
    clientId: clientId,
    state: state ?? this.state,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    margin: margin,
    leverage: leverage,
    targetCount: targetCount,
    systemMargin: systemMargin,
    systemLeverage: systemLeverage,
    systemTargetCount: systemTargetCount,
    entryOrderId: entryOrderId ?? this.entryOrderId,
    positionId: positionId ?? this.positionId,
    stopOrderId: stopOrderId ?? this.stopOrderId,
    targetOrderIds: List.unmodifiable(targetOrderIds ?? this.targetOrderIds),
    message: message ?? this.message,
  );

  Map<String, Object?> toJson() => {
    'setupId': setupId,
    'symbol': symbol,
    'clientId': clientId,
    'state': state.name,
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
    'margin': margin,
    'leverage': leverage,
    'targetCount': targetCount,
    'systemMargin': systemMargin,
    'systemLeverage': systemLeverage,
    'systemTargetCount': systemTargetCount,
    'entryOrderId': entryOrderId,
    'positionId': positionId,
    'stopOrderId': stopOrderId,
    'targetOrderIds': targetOrderIds,
    'message': message,
  };

  factory ManualTradeExecutionRecord.fromJson(Map<String, Object?> json) {
    final updatedAt = DateTime.tryParse(
      json['updatedAtUtc']?.toString() ?? '',
    )?.toUtc();
    final state = ManualTradeExecutionState.values
        .where((item) => item.name == json['state'])
        .firstOrNull;
    final setupId = json['setupId']?.toString().trim() ?? '';
    final symbol = json['symbol']?.toString().trim().toUpperCase() ?? '';
    final clientId = json['clientId']?.toString().trim() ?? '';
    final margin = (json['margin'] as num?)?.toDouble() ?? double.nan;
    final leverage = (json['leverage'] as num?)?.toInt() ?? 0;
    final targetCount = (json['targetCount'] as num?)?.toInt() ?? 0;
    final systemMargin = (json['systemMargin'] as num?)?.toDouble();
    final systemLeverage = (json['systemLeverage'] as num?)?.toInt();
    final systemTargetCount = (json['systemTargetCount'] as num?)?.toInt();
    if (updatedAt == null ||
        state == null ||
        setupId.isEmpty ||
        symbol.isEmpty ||
        !RegExp(r'^q-manual-[0-9a-f]{8}$').hasMatch(clientId) ||
        !margin.isFinite ||
        margin <= 0 ||
        leverage < 1 ||
        targetCount < 1 ||
        targetCount > 3) {
      throw const FormatException(
        'Manual trade execution record failed integrity validation.',
      );
    }
    return ManualTradeExecutionRecord(
      setupId: setupId,
      symbol: symbol,
      clientId: clientId,
      state: state,
      updatedAtUtc: updatedAt,
      margin: margin,
      leverage: leverage,
      targetCount: targetCount,
      systemMargin: systemMargin,
      systemLeverage: systemLeverage,
      systemTargetCount: systemTargetCount,
      entryOrderId: _nullable(json['entryOrderId']),
      positionId: _nullable(json['positionId']),
      stopOrderId: _nullable(json['stopOrderId']),
      targetOrderIds: (json['targetOrderIds'] as List<Object?>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      message: _nullable(json['message']),
    );
  }
}

abstract interface class ManualTradeExecutionStore {
  Future<ManualTradeExecutionRecord?> load(String setupId);
  Future<void> save(ManualTradeExecutionRecord record);
}

final class SharedPreferencesManualTradeExecutionStore
    implements ManualTradeExecutionStore {
  SharedPreferencesManualTradeExecutionStore({
    SharedPreferencesAsync? preferences,
    this.storageKey = 'quantara.manual-trade-execution.v1',
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  final String storageKey;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<ManualTradeExecutionRecord?> load(String setupId) async {
    await _writeTail;
    final raw = await _preferences.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) return null;
      final value = decoded[setupId];
      if (value is! Map<Object?, Object?>) return null;
      return ManualTradeExecutionRecord.fromJson(
        value.map((key, item) => MapEntry(key.toString(), item)),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(ManualTradeExecutionRecord record) {
    final operation = _writeTail.then((_) => _saveInternal(record));
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _saveInternal(ManualTradeExecutionRecord record) async {
    final raw = await _preferences.getString(storageKey);
    final records = <String, Object?>{};
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<Object?, Object?>) {
          for (final entry in decoded.entries) {
            records[entry.key.toString()] = entry.value;
          }
        }
      } on FormatException {
        // Fail closed for the old payload by replacing it with the new,
        // integrity-validated record rather than trusting malformed content.
      }
    }
    records[record.setupId] = record.toJson();
    await _preferences.setString(storageKey, jsonEncode(records));
  }
}

String? _nullable(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
