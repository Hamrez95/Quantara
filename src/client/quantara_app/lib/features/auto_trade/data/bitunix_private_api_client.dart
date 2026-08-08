import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/auto_trade_models.dart';
import '../domain/trading_pnl_projection.dart';
import 'bitunix_pnl_mapper.dart';
import 'bitunix_request_signer.dart';

final class BitunixPrivateApiClient {
  BitunixPrivateApiClient({
    required http.Client client,
    DateTime Function()? utcNow,
    Random? secureRandom,
  }) : this._(client, utcNow ?? DateTime.now, secureRandom ?? Random.secure());

  BitunixPrivateApiClient._(this._client, this._utcNow, this._random);

  static const _host = 'fapi.bitunix.com';
  static const _historyPageSize = 100;
  static const _historyMaxPages = 50;

  final http.Client _client;
  final DateTime Function() _utcNow;
  final Random _random;

  Future<AutoTradeAccountSnapshot> fetchAccountSnapshot(
    BitunixApiCredentials credentials,
  ) async {
    final accountResponse = await _signedGet('/api/v1/futures/account', const {
      'marginCoin': 'USDT',
    }, credentials);
    final positionsResponse = await _signedGet(
      '/api/v1/futures/position/get_pending_positions',
      const {},
      credentials,
    );
    final ordersResponse = await _signedGet(
      '/api/v1/futures/trade/get_pending_orders',
      const {'limit': '100'},
      credentials,
    );

    final account = _firstMap(accountResponse['data']);
    if (account == null) {
      throw const AutoTradeSafeException(
        'Bitunix account data was empty or malformed.',
      );
    }

    final positionMaps = _mapList(positionsResponse['data']);
    final positions = positionMaps
        .map(_positionFromJson)
        .toList(growable: false);
    final orderData = ordersResponse['data'];
    final orderMaps = orderData is Map<String, Object?>
        ? _mapList(orderData['orderList'])
        : const <Map<String, Object?>>[];
    final protectionOrders = <AutoTradeProtectionOrder>[];
    final protectionVerifications = <String, AutoTradeProtectionVerification>{};
    final unrealizedByPosition = <String, ExchangeUnrealizedPnl>{
      for (final position in positions)
        position.positionId: ExchangeUnrealizedPnl(
          positionId: position.positionId,
          symbol: position.symbol,
          value: position.unrealizedPnl,
          realizedPnl: position.realizedPnl,
          fee: position.fee,
          funding: position.funding,
        ),
    };

    for (final position in positions) {
      final positionId = position.positionId.trim();
      final attemptedAt = _utcNow().toUtc();
      if (positionId.isEmpty) {
        protectionVerifications[positionId] =
            AutoTradeProtectionVerification.unverified(
              asOf: attemptedAt,
              reason: 'Bitunix returned a position without a position ID.',
            );
        continue;
      }
      try {
        final response =
            await _signedGet('/api/v1/futures/tpsl/get_pending_orders', {
              'limit': '100',
              'positionId': positionId,
              'skip': '0',
              'symbol': position.symbol,
            }, credentials);
        final maps = _protectionMapList(response['data']);
        var verified = true;
        String? reason;
        for (final item in maps) {
          final itemPositionId = _string(item['positionId']);
          final exchangeId = _string(
            item['id'],
            fallback: _string(item['orderId']),
          );
          if (itemPositionId != positionId || exchangeId.isEmpty) {
            verified = false;
            reason = itemPositionId != positionId
                ? 'Bitunix returned a TP/SL row for a different position.'
                : 'Bitunix returned a TP/SL row without an exchange ID.';
            continue;
          }
          protectionOrders.add(_protectionOrderFromJson(item));
        }
        protectionVerifications[positionId] = verified
            ? AutoTradeProtectionVerification.verified(asOf: _utcNow().toUtc())
            : AutoTradeProtectionVerification.unverified(
                asOf: _utcNow().toUtc(),
                reason: reason ?? 'Position TP/SL response was ambiguous.',
              );
      } on AutoTradeSafeException catch (error) {
        protectionVerifications[positionId] =
            AutoTradeProtectionVerification.unverified(
              asOf: _utcNow().toUtc(),
              reason: error.message,
            );
      }
    }

    var settlementsAvailable = true;
    var fillsAvailable = true;
    var sourceVerified = true;
    final pnlWarnings = <String>[];
    List<ExchangePositionSettlement> settlements = const [];
    List<ExchangePnlFill> fills = const [];
    try {
      final data = await _signedGetCompleteHistory(
        path: '/api/v1/futures/position/get_history_positions',
        listKey: 'positionList',
        identityKey: 'positionId',
        credentials: credentials,
      );
      final parsed = BitunixPnlMapper.settlements(data);
      settlements = parsed.values;
      sourceVerified = sourceVerified && parsed.verified;
      if (parsed.warning != null) pnlWarnings.add(parsed.warning!);
    } on AutoTradeSafeException catch (error) {
      settlementsAvailable = false;
      pnlWarnings.add(error.message);
    }
    try {
      final data = await _signedGetCompleteHistory(
        path: '/api/v1/futures/trade/get_history_trades',
        listKey: 'tradeList',
        identityKey: 'tradeId',
        credentials: credentials,
      );
      final parsed = BitunixPnlMapper.fills(
        data,
        openPositions: unrealizedByPosition.values,
        settlements: settlements,
      );
      fills = parsed.values;
      sourceVerified = sourceVerified && parsed.verified;
      if (parsed.warning != null) pnlWarnings.add(parsed.warning!);
    } on AutoTradeSafeException catch (error) {
      fillsAvailable = false;
      sourceVerified = false;
      pnlWarnings.add(error.message);
    }
    final pnlAsOf = _utcNow().toUtc();
    final pnlProjection = TradingPnlProjection.reconcile(
      currency: _string(account['marginCoin'], fallback: 'USDT'),
      asOf: pnlAsOf,
      unrealizedByPosition: unrealizedByPosition,
      fills: fills,
      settlements: settlements,
      fillsAvailable: fillsAvailable,
      settlementsAvailable: settlementsAvailable,
      sourceVerified: sourceVerified,
      warning: pnlWarnings.isEmpty ? null : pnlWarnings.toSet().join(' '),
    );

    return AutoTradeAccountSnapshot(
      marginCoin: _string(account['marginCoin'], fallback: 'USDT'),
      available: _number(account['available']),
      frozen: _number(account['frozen']),
      positionMargin: _number(account['margin']),
      crossUnrealizedPnl: _number(account['crossUnrealizedPNL']),
      isolatedUnrealizedPnl: _number(account['isolationUnrealizedPNL']),
      positionMode: _string(account['positionMode'], fallback: 'UNKNOWN'),
      positions: positions,
      orders: orderMaps.map(_orderFromJson).toList(growable: false),
      protectionOrders: List.unmodifiable(protectionOrders),
      protectionVerifications: Map.unmodifiable(protectionVerifications),
      pnlProjection: pnlProjection,
      syncedAt: pnlAsOf,
    );
  }

  Future<Map<String, Object?>> _signedGetCompleteHistory({
    required String path,
    required String listKey,
    required String identityKey,
    required BitunixApiCredentials credentials,
  }) async {
    final rows = <Map<String, Object?>>[];
    final seenIdentities = <String>{};
    var skip = 0;
    int? total;

    for (var page = 0; page < _historyMaxPages; page += 1) {
      final response = await _signedGet(path, {
        'limit': '$_historyPageSize',
        'skip': '$skip',
      }, credentials);
      final data = _map(response['data']);
      if (data == null) {
        throw const AutoTradeSafeException(
          'Bitunix history data was empty or malformed.',
        );
      }
      final pageRows = _mapList(data[listKey]);
      final pageTotal = _optionalInteger(data['total']);
      if (pageTotal != null && pageTotal >= 0) total = pageTotal;

      for (var index = 0; index < pageRows.length; index += 1) {
        final row = pageRows[index];
        final identity = _string(row[identityKey]);
        if (identity.isEmpty) {
          // Preserve malformed rows so the mapper can mark source quality
          // unverified instead of silently hiding bad exchange data.
          rows.add(row);
          continue;
        }
        if (seenIdentities.add(identity)) rows.add(row);
      }

      skip += pageRows.length;
      final reachedReportedTotal = total != null && skip >= total!;
      if (pageRows.isEmpty ||
          pageRows.length < _historyPageSize ||
          reachedReportedTotal) {
        return <String, Object?>{
          listKey: List.unmodifiable(rows),
          'total': total ?? skip,
        };
      }

      if (page + 1 >= _historyMaxPages) {
        throw AutoTradeSafeException(
          'Bitunix $listKey history exceeded the verified pagination safety bound; full history was not claimed.',
        );
      }

      // Both history endpoints are rate-limited. Sequential paging plus this
      // guard stays comfortably below the documented per-UID request ceiling.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    throw AutoTradeSafeException(
      'Bitunix $listKey history pagination ended without a verified boundary.',
    );
  }

  Future<Map<String, Object?>> _signedGet(
    String path,
    Map<String, String> query,
    BitunixApiCredentials credentials,
  ) async {
    final sortedEntries = query.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final sortedQuery = <String, String>{
      for (final entry in sortedEntries) entry.key: entry.value,
    };
    final nonce = _nonce();
    final timestamp = _utcNow().toUtc().millisecondsSinceEpoch.toString();
    final signature = BitunixRequestSigner.create(
      nonce: nonce,
      timestamp: timestamp,
      apiKey: credentials.apiKey,
      secretKey: credentials.secretKey,
      query: sortedQuery,
    );
    final uri = Uri.https(_host, path, sortedQuery);

    late final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'api-key': credentials.apiKey,
              'nonce': nonce,
              'timestamp': timestamp,
              'sign': signature.sign,
              'language': 'en-US',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 18));
    } on Object {
      throw const AutoTradeSafeException(
        'Could not reach the Bitunix private API.',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw AutoTradeSafeException(
        'Bitunix returned an unreadable response.',
        code: response.statusCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw AutoTradeSafeException(
        'Bitunix returned an unexpected response shape.',
        code: response.statusCode,
      );
    }

    final code = decoded['code'];
    final successCode = code == 0 || code == '0';
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        !successCode) {
      throw AutoTradeSafeException(
        _safeMessage(decoded['msg']),
        code: code ?? response.statusCode,
      );
    }
    return decoded;
  }

  String _nonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static AutoTradePosition _positionFromJson(Map<String, Object?> value) =>
      AutoTradePosition(
        positionId: _string(value['positionId']),
        symbol: _string(value['symbol']),
        quantity: _number(value['qty']),
        side: _string(value['side'], fallback: 'UNKNOWN'),
        marginMode: _string(value['marginMode'], fallback: 'UNKNOWN'),
        positionMode: _string(value['positionMode'], fallback: 'UNKNOWN'),
        leverage: _integer(value['leverage'], fallback: 1),
        margin: _number(value['margin']),
        unrealizedPnl: _number(value['unrealizedPNL']),
        liquidationPrice: _number(value['liqPrice']),
        averageOpenPrice: _number(value['avgOpenPrice']),
        realizedPnl: _optionalNumber(value['realizedPNL']),
        fee: _optionalNumber(value['fee']),
        funding: _optionalNumber(value['funding']),
        openedAt: _timestamp(value['ctime']),
      );

  static AutoTradeOrder _orderFromJson(Map<String, Object?> value) =>
      AutoTradeOrder(
        orderId: _string(value['orderId']),
        clientId: _string(value['clientId']),
        symbol: _string(value['symbol']),
        quantity: _number(value['qty']),
        filledQuantity: _number(value['tradeQty']),
        side: _string(value['side'], fallback: 'UNKNOWN'),
        orderType: _string(value['orderType'], fallback: 'UNKNOWN'),
        marginMode: _string(value['marginMode'], fallback: 'UNKNOWN'),
        leverage: _integer(value['leverage'], fallback: 1),
        reduceOnly: value['reduceOnly'] == true,
      );

  static AutoTradeProtectionOrder _protectionOrderFromJson(
    Map<String, Object?> value,
  ) => AutoTradeProtectionOrder(
    exchangeId: _string(value['id'], fallback: _string(value['orderId'])),
    positionId: _string(value['positionId']),
    symbol: _string(value['symbol']),
    takeProfitPrice: _optionalPositiveNumber(value['tpPrice']),
    takeProfitQuantity: _optionalPositiveNumber(value['tpQty']),
    takeProfitStopType: _optionalString(value['tpStopType']),
    takeProfitOrderType: _optionalString(value['tpOrderType']),
    stopLossPrice: _optionalPositiveNumber(value['slPrice']),
    stopLossQuantity: _optionalPositiveNumber(value['slQty']),
    stopLossStopType: _optionalString(value['slStopType']),
    stopLossOrderType: _optionalString(value['slOrderType']),
  );

  static List<Map<String, Object?>> _protectionMapList(Object? value) {
    if (value is List<Object?>) return _mapList(value);
    if (value is Map<String, Object?> && value['orderList'] is List<Object?>) {
      return _mapList(value['orderList']);
    }
    throw const AutoTradeSafeException(
      'Bitunix position TP/SL data was empty or malformed.',
    );
  }

  static Map<String, Object?>? _firstMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    final values = _mapList(value);
    return values.isEmpty ? null : values.first;
  }

  static Map<String, Object?>? _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map<Object?, Object?>) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return null;
  }

  static List<Map<String, Object?>> _mapList(Object? value) {
    if (value is! List<Object?>) return const [];
    return value
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) =>
              item.map((key, itemValue) => MapEntry(key.toString(), itemValue)),
        )
        .toList(growable: false);
  }

  static double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _optionalNumber(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static int? _optionalInteger(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  static DateTime? _timestamp(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
  }

  static double? _optionalPositiveNumber(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    return parsed;
  }

  static String? _optionalString(Object? value) {
    final parsed = value?.toString().trim() ?? '';
    return parsed.isEmpty ? null : parsed;
  }

  static int _integer(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _string(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _safeMessage(Object? value) {
    final text = _string(value, fallback: 'Bitunix rejected the request.');
    return text.length <= 180 ? text : '${text.substring(0, 180)}…';
  }
}