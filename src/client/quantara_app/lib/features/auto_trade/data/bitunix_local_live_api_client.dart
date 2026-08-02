import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../domain/auto_trade_models.dart';
import '../domain/local_live_trade_models.dart';
import 'bitunix_request_signer.dart';

final class BitunixInstrumentRules {
  const BitunixInstrumentRules({
    required this.symbol,
    required this.minimumQuantity,
    required this.maximumMarketQuantity,
    required this.quantityPrecision,
    required this.pricePrecision,
    required this.minimumLeverage,
    required this.maximumLeverage,
    required this.open,
    required this.apiSupported,
  });

  final String symbol;
  final double minimumQuantity;
  final double maximumMarketQuantity;
  final int quantityPrecision;
  final int pricePrecision;
  final int minimumLeverage;
  final int maximumLeverage;
  final bool open;
  final bool apiSupported;

  double roundQuantityDown(double value) {
    final factor = pow(10, quantityPrecision).toDouble();
    return (value * factor).floor() / factor;
  }

  double roundPrice(double value) {
    final factor = pow(10, pricePrecision).toDouble();
    return (value * factor).round() / factor;
  }
}

final class BitunixLivePosition {
  const BitunixLivePosition({
    required this.positionId,
    required this.symbol,
    required this.quantity,
    required this.side,
    required this.marginMode,
    required this.positionMode,
    required this.leverage,
    required this.averageOpenPrice,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.fee,
    required this.funding,
  });

  final String positionId;
  final String symbol;
  final double quantity;
  final String side;
  final String marginMode;
  final String positionMode;
  final int leverage;
  final double averageOpenPrice;
  final double realizedPnl;
  final double unrealizedPnl;
  final double fee;
  final double funding;
}

final class BitunixOrderDetail {
  const BitunixOrderDetail({
    required this.orderId,
    required this.clientId,
    required this.symbol,
    required this.quantity,
    required this.filledQuantity,
    required this.status,
    required this.fee,
    required this.realizedPnl,
  });

  final String orderId;
  final String clientId;
  final String symbol;
  final double quantity;
  final double filledQuantity;
  final String status;
  final double fee;
  final double realizedPnl;

  bool get hasFill => filledQuantity > 0;
  bool get fullyFilled => status == 'FILLED';
}

final class BitunixPlacedOrder {
  const BitunixPlacedOrder({required this.orderId, required this.clientId});

  final String orderId;
  final String clientId;
}

final class BitunixPendingProtection {
  const BitunixPendingProtection({
    required this.orderId,
    required this.positionId,
    required this.symbol,
    required this.takeProfitPrice,
    required this.stopLossPrice,
    required this.takeProfitQuantity,
    required this.stopLossQuantity,
  });

  final String orderId;
  final String positionId;
  final String symbol;
  final double takeProfitPrice;
  final double stopLossPrice;
  final double takeProfitQuantity;
  final double stopLossQuantity;
}

final class BitunixClosedPosition {
  const BitunixClosedPosition({
    required this.positionId,
    required this.symbol,
    required this.realizedPnl,
    required this.fee,
    required this.funding,
  });

  final String positionId;
  final String symbol;
  final double realizedPnl;
  final double fee;
  final double funding;

  double get netPnl => realizedPnl - fee + funding;
}

final class BitunixLocalLiveApiClient {
  BitunixLocalLiveApiClient({
    required this._client,
    DateTime Function()? utcNow,
    Random? secureRandom,
  }) : _utcNow = utcNow ?? DateTime.now,
       _random = secureRandom ?? Random.secure();

  static const _host = 'fapi.bitunix.com';

  final http.Client _client;
  final DateTime Function() _utcNow;
  final Random _random;

  Future<double> fetchMarkPrice(String symbol) async {
    final payload = await _publicGet('/api/v1/futures/market/tickers', {
      'symbols': symbol,
    });
    final item = _mapList(payload['data']).firstWhere(
      (value) => _string(value['symbol']) == symbol,
      orElse: () => const {},
    );
    final price = _number(item['markPrice']);
    if (price <= 0) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not return a valid mark price.',
      );
    }
    return price;
  }

  Future<BitunixInstrumentRules> fetchInstrumentRules(String symbol) async {
    final payload = await _publicGet('/api/v1/futures/market/trading_pairs', {
      'symbols': symbol,
    });
    final item = _mapList(payload['data']).firstWhere(
      (value) => _string(value['symbol']) == symbol,
      orElse: () => const {},
    );
    if (item.isEmpty) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not return symbol trading rules.',
      );
    }
    return BitunixInstrumentRules(
      symbol: symbol,
      minimumQuantity: _number(item['minTradeVolume']),
      maximumMarketQuantity: _number(item['maxMarketOrderVolume']),
      quantityPrecision: _integer(item['basePrecision'], fallback: 8),
      pricePrecision: _integer(item['quotePrecision'], fallback: 8),
      minimumLeverage: _integer(item['minLeverage'], fallback: 1),
      maximumLeverage: _integer(item['maxLeverage'], fallback: 1),
      open: _string(item['symbolStatus']).toUpperCase() == 'OPEN',
      apiSupported: item['isApiSupported'] == true,
    );
  }

  Future<AutoTradeAccountSnapshot> fetchAccountSnapshot(
    BitunixApiCredentials credentials,
  ) async {
    final accountResponse = await _signedGet('/api/v1/futures/account', {
      'marginCoin': 'USDT',
    }, credentials);
    final positions = await fetchPositions(credentials);
    final ordersResponse = await _signedGet(
      '/api/v1/futures/trade/get_pending_orders',
      const {'limit': '100'},
      credentials,
    );
    final account = _firstMap(accountResponse['data']);
    if (account == null) {
      throw const LocalLiveTradeSafeException(
        'Bitunix account data was empty or malformed.',
      );
    }
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
            ),
          )
          .toList(growable: false),
      orders: orderMaps.map(_orderFromJson).toList(growable: false),
      syncedAt: _utcNow().toUtc(),
    );
  }

  Future<List<BitunixLivePosition>> fetchPositions(
    BitunixApiCredentials credentials, {
    String? symbol,
  }) async {
    final response = await _signedGet(
      '/api/v1/futures/position/get_pending_positions',
      symbol == null ? const {} : {'symbol': symbol},
      credentials,
    );
    return _mapList(
      response['data'],
    ).map(_positionFromJson).toList(growable: false);
  }

  Future<List<BitunixPendingProtection>> fetchPendingProtection(
    BitunixApiCredentials credentials, {
    String? symbol,
    String? positionId,
  }) async {
    final query = <String, String>{'limit': '100'};
    if (symbol != null) query['symbol'] = symbol;
    if (positionId != null) query['positionId'] = positionId;
    final response = await _signedGet(
      '/api/v1/futures/tpsl/get_pending_orders',
      query,
      credentials,
    );
    final data = response['data'];
    final list = data is Map<String, Object?>
        ? _mapList(data['orderList'])
        : _mapList(data);
    return list
        .map(
          (item) => BitunixPendingProtection(
            orderId: _string(item['id'], fallback: _string(item['orderId'])),
            positionId: _string(item['positionId']),
            symbol: _string(item['symbol']),
            takeProfitPrice: _number(item['tpPrice']),
            stopLossPrice: _number(item['slPrice']),
            takeProfitQuantity: _number(item['tpQty']),
            stopLossQuantity: _number(item['slQty']),
          ),
        )
        .toList(growable: false);
  }

  Future<BitunixOrderDetail> fetchOrderDetail({
    required String orderId,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedGet(
      '/api/v1/futures/trade/get_order_detail',
      {'orderId': orderId},
      credentials,
    );
    final item = _firstMap(response['data']);
    if (item == null) {
      throw const LocalLiveTradeSafeException(
        'Bitunix order detail was empty.',
      );
    }
    return BitunixOrderDetail(
      orderId: _string(item['orderId']),
      clientId: _string(item['clientId']),
      symbol: _string(item['symbol']),
      quantity: _number(item['qty']),
      filledQuantity: _number(item['tradeQty']),
      status: _string(item['status']).toUpperCase(),
      fee: _number(item['fee']),
      realizedPnl: _number(item['realizedPNL']),
    );
  }

  Future<List<BitunixClosedPosition>> fetchClosedPositions({
    required String positionId,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedGet(
      '/api/v1/futures/position/get_history_positions',
      {'positionId': positionId, 'limit': '10'},
      credentials,
    );
    final data = response['data'];
    final list = data is Map<String, Object?>
        ? _mapList(data['positionList'])
        : _mapList(data);
    return list
        .map(
          (item) => BitunixClosedPosition(
            positionId: _string(item['positionId']),
            symbol: _string(item['symbol']),
            realizedPnl: _number(item['realizedPNL']),
            fee: _number(item['fee']),
            funding: _number(item['funding']),
          ),
        )
        .toList(growable: false);
  }

  Future<void> ensureIsolatedMargin({
    required String symbol,
    required BitunixApiCredentials credentials,
  }) async {
    final modeResponse = await _signedGet(
      '/api/v1/futures/account/get_leverage_margin_mode',
      {'marginCoin': 'USDT', 'symbol': symbol},
      credentials,
    );
    final mode = _firstMap(modeResponse['data']);
    if (_string(mode?['marginMode']).toUpperCase() == 'ISOLATION') return;
    await _signedPost(
      '/api/v1/futures/account/change_margin_mode',
      SplayTreeMap<String, Object?>.from({
        'marginCoin': 'USDT',
        'marginMode': 'ISOLATION',
        'symbol': symbol,
      }),
      credentials,
    );
  }

  Future<void> changeLeverage({
    required String symbol,
    required int leverage,
    required BitunixApiCredentials credentials,
  }) async {
    await _signedPost(
      '/api/v1/futures/account/change_leverage',
      SplayTreeMap<String, Object?>.from({
        'leverage': leverage,
        'marginCoin': 'USDT',
        'symbol': symbol,
      }),
      credentials,
    );
  }

  Future<BitunixPlacedOrder> placeMarketEntry({
    required String symbol,
    required double quantity,
    required bool long,
    required String clientId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/trade/place_order',
      SplayTreeMap<String, Object?>.from({
        'clientId': clientId,
        'orderType': 'MARKET',
        'qty': _decimal(quantity),
        'reduceOnly': false,
        'side': long ? 'BUY' : 'SELL',
        'slOrderType': 'MARKET',
        'slPrice': _decimal(stopLoss),
        'slStopType': 'MARK_PRICE',
        'symbol': symbol,
        'tradeSide': 'OPEN',
      }),
      credentials,
    );
    final data = _firstMap(response['data']);
    if (data == null) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not return an entry order ID.',
      );
    }
    return BitunixPlacedOrder(
      orderId: _string(data['orderId']),
      clientId: _string(data['clientId'], fallback: clientId),
    );
  }

  Future<void> cancelEntryOrder({
    required String symbol,
    required String orderId,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/trade/cancel_orders',
      SplayTreeMap<String, Object?>.from({
        'orderList': [
          {'clientId': clientId, 'orderId': orderId},
        ],
        'symbol': symbol,
      }),
      credentials,
    );
    final data = response['data'];
    final failures = data is Map<String, Object?>
        ? _mapList(data['failureList'])
        : const <Map<String, Object?>>[];
    if (failures.isNotEmpty) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not confirm cancellation of the unresolved entry.',
      );
    }
  }

  Future<String> placePositionStop({
    required String symbol,
    required String positionId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/tpsl/position/place_order',
      SplayTreeMap<String, Object?>.from({
        'positionId': positionId,
        'slPrice': _decimal(stopLoss),
        'slStopType': 'MARK_PRICE',
        'symbol': symbol,
      }),
      credentials,
    );
    return _requiredOrderId(response);
  }

  Future<String> modifyPositionStop({
    required String symbol,
    required String positionId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/tpsl/position/modify_order',
      SplayTreeMap<String, Object?>.from({
        'positionId': positionId,
        'slPrice': _decimal(stopLoss),
        'slStopType': 'MARK_PRICE',
        'symbol': symbol,
      }),
      credentials,
    );
    return _requiredOrderId(response);
  }

  Future<String> placePartialTakeProfit({
    required String symbol,
    required String positionId,
    required double triggerPrice,
    required double quantity,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/tpsl/place_order',
      SplayTreeMap<String, Object?>.from({
        'positionId': positionId,
        'symbol': symbol,
        'tpOrderType': 'MARKET',
        'tpPrice': _decimal(triggerPrice),
        'tpQty': _decimal(quantity),
        'tpStopType': 'MARK_PRICE',
      }),
      credentials,
    );
    return _requiredOrderId(response);
  }

  Future<BitunixPlacedOrder> closePositionReduceOnly({
    required BitunixLivePosition position,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/trade/flash_close_position',
      SplayTreeMap<String, Object?>.from({'positionId': position.positionId}),
      credentials,
    );
    final data = _firstMap(response['data']);
    final positionId = _string(data?['positionId']);
    if (positionId.isEmpty) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not confirm the emergency position close.',
      );
    }
    return BitunixPlacedOrder(orderId: positionId, clientId: clientId);
  }

  Future<Map<String, Object?>> _publicGet(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.https(_host, path, query);
    return _decode(await _client.get(uri).timeout(const Duration(seconds: 18)));
  }

  Future<Map<String, Object?>> _signedGet(
    String path,
    Map<String, String> query,
    BitunixApiCredentials credentials,
  ) async {
    final sorted = SplayTreeMap<String, String>.from(query);
    final nonce = _nonce();
    final timestamp = _utcNow().toUtc().millisecondsSinceEpoch.toString();
    final signature = BitunixRequestSigner.create(
      nonce: nonce,
      timestamp: timestamp,
      apiKey: credentials.apiKey,
      secretKey: credentials.secretKey,
      query: sorted,
    );
    final uri = Uri.https(_host, path, sorted);
    return _decode(
      await _client
          .get(uri, headers: _headers(credentials, nonce, timestamp, signature))
          .timeout(const Duration(seconds: 18)),
    );
  }

  Future<Map<String, Object?>> _signedPost(
    String path,
    SplayTreeMap<String, Object?> body,
    BitunixApiCredentials credentials,
  ) async {
    final encoded = jsonEncode(body);
    final nonce = _nonce();
    final timestamp = _utcNow().toUtc().millisecondsSinceEpoch.toString();
    final signature = BitunixRequestSigner.create(
      nonce: nonce,
      timestamp: timestamp,
      apiKey: credentials.apiKey,
      secretKey: credentials.secretKey,
      body: encoded,
    );
    return _decode(
      await _client
          .post(
            Uri.https(_host, path),
            headers: _headers(credentials, nonce, timestamp, signature),
            body: encoded,
          )
          .timeout(const Duration(seconds: 18)),
    );
  }

  Map<String, String> _headers(
    BitunixApiCredentials credentials,
    String nonce,
    String timestamp,
    BitunixSignature signature,
  ) => {
    'api-key': credentials.apiKey,
    'nonce': nonce,
    'timestamp': timestamp,
    'sign': signature.sign,
    'language': 'en-US',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, Object?> _decode(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw LocalLiveTradeSafeException(
        'Bitunix returned an unreadable response.',
        code: response.statusCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw LocalLiveTradeSafeException(
        'Bitunix returned an unexpected response shape.',
        code: response.statusCode,
      );
    }
    final code = decoded['code'];
    final success = code == 0 || code == '0';
    if (response.statusCode < 200 || response.statusCode >= 300 || !success) {
      throw LocalLiveTradeSafeException(
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

  static String _requiredOrderId(Map<String, Object?> response) {
    final data = _firstMap(response['data']);
    final id = _string(data?['orderId'], fallback: _string(data?['id']));
    if (id.isEmpty) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not return a protection order ID.',
      );
    }
    return id;
  }

  static BitunixLivePosition _positionFromJson(Map<String, Object?> item) =>
      BitunixLivePosition(
        positionId: _string(item['positionId']),
        symbol: _string(item['symbol']),
        quantity: _number(item['qty']).abs(),
        side: _string(item['side']).toUpperCase(),
        marginMode: _string(item['marginMode']).toUpperCase(),
        positionMode: _string(item['positionMode']).toUpperCase(),
        leverage: _integer(item['leverage'], fallback: 1),
        averageOpenPrice: _number(item['avgOpenPrice']),
        realizedPnl: _number(item['realizedPNL']),
        unrealizedPnl: _number(item['unrealizedPNL']),
        fee: _number(item['fee']),
        funding: _number(item['funding']),
      );

  static AutoTradeOrder _orderFromJson(Map<String, Object?> item) =>
      AutoTradeOrder(
        orderId: _string(item['orderId']),
        clientId: _string(item['clientId']),
        symbol: _string(item['symbol']),
        quantity: _number(item['qty']),
        filledQuantity: _number(item['tradeQty']),
        side: _string(item['side'], fallback: 'UNKNOWN'),
        orderType: _string(item['orderType'], fallback: 'UNKNOWN'),
        marginMode: _string(item['marginMode'], fallback: 'UNKNOWN'),
        leverage: _integer(item['leverage'], fallback: 1),
        reduceOnly: item['reduceOnly'] == true,
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

  static String _decimal(double value) {
    if (!value.isFinite) {
      throw const LocalLiveTradeSafeException('Order value was not finite.');
    }
    final fixed = value.toStringAsFixed(12);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
