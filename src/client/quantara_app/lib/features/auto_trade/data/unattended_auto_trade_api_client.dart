import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/unattended_auto_trade_models.dart';

final class UnattendedAutoTradeSafeException implements Exception {
  const UnattendedAutoTradeSafeException(this.message, {this.code});

  final String message;
  final Object? code;

  @override
  String toString() => message;
}

final class UnattendedAutoTradeApiClient {
  const UnattendedAutoTradeApiClient({required http.Client client})
    : _client = client;

  final http.Client _client;

  Future<UnattendedRunSnapshot> fetchStatus(
    AutoTradeServerConfig config,
  ) async {
    final decoded = await _send(
      config: config,
      method: 'GET',
      path: '/api/v1/auto-trade/status',
    );
    return UnattendedRunSnapshot.fromJson(decoded);
  }

  Future<UnattendedRunSnapshot> start({
    required AutoTradeServerConfig serverConfig,
    required UnattendedRunConfiguration configuration,
    required String requestId,
  }) async {
    final errors = configuration.validate();
    if (errors.isNotEmpty) {
      throw UnattendedAutoTradeSafeException(errors.join('\n'));
    }
    final decoded = await _send(
      config: serverConfig,
      method: 'POST',
      path: '/api/v1/auto-trade/start',
      body: configuration.toJson(requestId: requestId),
    );
    return _snapshotFromTransition(decoded);
  }

  Future<UnattendedRunSnapshot> stop({
    required AutoTradeServerConfig serverConfig,
    required String requestId,
    required UnattendedStopPolicy policy,
    required bool hasOpenPositionsOrOrders,
    required String reason,
  }) async {
    final decoded = await _send(
      config: serverConfig,
      method: 'POST',
      path: '/api/v1/auto-trade/stop',
      body: {
        'requestId': requestId,
        'policy': policy.serverName,
        'hasOpenPositionsOrOrders': hasOpenPositionsOrOrders,
        'reason': reason,
      },
    );
    return _snapshotFromTransition(decoded);
  }

  Future<Map<String, Object?>> _send({
    required AutoTradeServerConfig config,
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    final uri = config.baseUrl.resolve(path);
    late final http.Response response;
    try {
      final headers = {
        'Accept': 'application/json',
        'X-Quantara-Control-Token': config.controlToken,
        if (body != null) 'Content-Type': 'application/json',
      };
      response = method == 'GET'
          ? await _client
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 15))
          : await _client
                .post(uri, headers: headers, body: jsonEncode(body))
                .timeout(const Duration(seconds: 18));
    } on Object {
      throw const UnattendedAutoTradeSafeException(
        'The always-on Quantara trading server could not be reached.',
      );
    }

    if (response.bodyBytes.length > 1000000) {
      throw const UnattendedAutoTradeSafeException(
        'The trading server returned an oversized response.',
      );
    }
    Object? value;
    try {
      value = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw UnattendedAutoTradeSafeException(
        'The trading server returned an unreadable response.',
        code: response.statusCode,
      );
    }
    if (value is! Map<String, Object?>) {
      throw UnattendedAutoTradeSafeException(
        'The trading server returned an unexpected response.',
        code: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = value['errors'];
      final errorText = errors is List
          ? errors.map((item) => item.toString()).join('\n')
          : 'The trading server rejected the request.';
      throw UnattendedAutoTradeSafeException(
        errorText,
        code: response.statusCode,
      );
    }
    return value;
  }

  static UnattendedRunSnapshot _snapshotFromTransition(
    Map<String, Object?> json,
  ) {
    final snapshot = json['snapshot'];
    if (snapshot is! Map<String, Object?>) {
      throw const UnattendedAutoTradeSafeException(
        'The trading server did not return a run snapshot.',
      );
    }
    return UnattendedRunSnapshot.fromJson(snapshot);
  }
}
