import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/auto_trade_models.dart';
import 'bitunix_request_signer.dart';

final class BitunixPrivateApiClient {
  BitunixPrivateApiClient({
    required http.Client client,
    DateTime Function()? utcNow,
    Random? secureRandom,
  }) : this._(
         client,
         utcNow ?? DateTime.now,
         secureRandom ?? Random.secure(),
       );

  BitunixPrivateApiClient._(this._client, this._utcNow, this._random);

  static const _host = 'fapi.bitunix.com';

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
    final orderData = ordersResponse['data'];
    final orderMaps = orderData is Map<String, Object?>
        ? _mapList(orderData['orderList'])
        : const <Map<String, Object?>>[];

    return AutoTradeAccountSnapshot(
      marginCoin: _string(account['marginCoin'], fallback: 'USDT'),
      available: _number(account['available']),
      frozen: _number(account['frozen']),
      positionMargin: _number(account['margin']),
      crossUnrealizedPnl: _number(account['crossUnrealizedPNL']),
      isolatedUnrealizedPnl: _number(account['isolationUnrealizedPNL']),
      positionMode: _string(account['positionMode'], fallback: 'UNKNOWN'),
      positions: positionMaps.map(_positionFromJson).toList(growable: false),
      orders: orderMaps.map(_orderFromJson).toList(growable: false),
      syncedAt: _utcNow().toUtc(),
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

  static Map<String, Object?>? _firstMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    final values = _mapList(value);
    return values.isEmpty ? null : values.first;
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
