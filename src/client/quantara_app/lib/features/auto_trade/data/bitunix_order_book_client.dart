import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bitunix_order_book_top.dart';

final class BitunixOrderBookClient {
  factory BitunixOrderBookClient({required http.Client client}) =>
      BitunixOrderBookClient._(client);

  BitunixOrderBookClient._(this._client);

  static const _host = 'fapi.bitunix.com';
  static const _depthPath = '/api/v1/futures/market/depth';

  final http.Client _client;

  Future<BitunixOrderBookTop> fetchTopOfBook(String symbol) async {
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedSymbol.isEmpty) {
      throw const FormatException('Bitunix order book symbol is required.');
    }
    final uri = Uri.https(_host, _depthPath, {
      'symbol': normalizedSymbol,
      'limit': '1',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FormatException('Bitunix order book request failed.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FormatException('Bitunix order book response is invalid.');
    }
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Bitunix order book response is invalid.');
    }
    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final code = payload['code'];
    final parsedCode = code is num
        ? code.toInt()
        : int.tryParse(code.toString());
    if (parsedCode != 0) {
      throw const FormatException('Bitunix order book request was rejected.');
    }
    return BitunixOrderBookTop.fromApiPayload(payload);
  }
}
