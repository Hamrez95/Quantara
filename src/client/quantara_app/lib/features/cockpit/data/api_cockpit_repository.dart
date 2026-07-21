import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/cockpit_models.dart';

sealed class CockpitRepositoryException implements Exception {
  const CockpitRepositoryException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class CockpitTransportException extends CockpitRepositoryException {
  const CockpitTransportException(super.message);
}

final class CockpitContractException extends CockpitRepositoryException {
  const CockpitContractException(super.message);
}

final class ApiCockpitRepository implements CockpitRepository {
  factory ApiCockpitRepository({
    required http.Client client,
    required Uri endpoint,
    Duration timeout = const Duration(seconds: 8),
    DateTime Function()? now,
  }) {
    return ApiCockpitRepository._(
      client,
      endpoint,
      timeout,
      now ?? DateTime.now,
    );
  }

  ApiCockpitRepository._(
    this._client,
    this._endpoint,
    this._timeout,
    this._now,
  ) {
    final localDevelopmentHost =
        _endpoint.host == 'localhost' ||
        _endpoint.host == '127.0.0.1' ||
        _endpoint.host == '::1' ||
        _endpoint.host == '10.0.2.2';
    final secureTransport =
        _endpoint.scheme == 'https' ||
        (!kReleaseMode && _endpoint.scheme == 'http' && localDevelopmentHost);
    if (!secureTransport ||
        _endpoint.userInfo.isNotEmpty ||
        _endpoint.host.isEmpty ||
        _endpoint.path != '/api/v1/cockpit' ||
        _endpoint.hasQuery ||
        _endpoint.hasFragment) {
      throw const CockpitContractException(
        'The cockpit endpoint must be a safe credential-free v1 endpoint.',
      );
    }
    if (_timeout <= Duration.zero || _timeout > const Duration(seconds: 30)) {
      throw const CockpitContractException(
        'The cockpit timeout must be between zero and 30 seconds.',
      );
    }
  }

  static const _maximumResponseBytes = 1_048_576;

  final http.Client _client;
  final Uri _endpoint;
  final Duration _timeout;
  final DateTime Function() _now;

  @override
  Future<CockpitSnapshot> load() async {
    late http.Response response;
    try {
      response = await _client
          .get(_endpoint, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw CockpitTransportException('API request timed out: $error');
    } on http.ClientException catch (error) {
      throw CockpitTransportException('API request failed: $error');
    }

    if (response.statusCode >= 500 ||
        response.statusCode == 408 ||
        response.statusCode == 429) {
      throw CockpitTransportException(
        'API is temporarily unavailable (${response.statusCode}).',
      );
    }
    if (response.statusCode != 200) {
      throw CockpitContractException(
        'Unexpected API status ${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > _maximumResponseBytes) {
      throw const CockpitContractException('API response is too large.');
    }

    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType != 'application/json') {
      throw const CockpitContractException(
        'API response must use application/json.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw CockpitContractException('API returned invalid JSON: $error');
    }

    return _CockpitParser(now: _now().toUtc()).parse(decoded);
  }
}

final class FallbackCockpitRepository implements CockpitRepository {
  const FallbackCockpitRepository(this._primary, this._fallback);

  final CockpitRepository _primary;
  final CockpitRepository _fallback;

  @override
  Future<CockpitSnapshot> load() async {
    try {
      return await _primary.load();
    } on CockpitTransportException {
      return _fallback.load();
    }
  }
}

final class _CockpitParser {
  const _CockpitParser({required this.now});

  static final _symbolPattern = RegExp(r'^[A-Z0-9]{3,24}$');
  static const _maximumMoneyValue = 1e15;

  final DateTime now;

  CockpitSnapshot parse(Object? value) {
    final root = _object(value, 'root');
    _expectString(root, 'schemaVersion', allowed: const {'cockpit-v1'});
    _expectString(root, 'language', allowed: const {'fa'});
    _expectString(root, 'environment', allowed: const {'demo'});
    _expectString(
      root,
      'dataSourceMode',
      allowed: const {'deterministic_demo'},
    );
    final marketStatusCode = _expectString(root, 'marketStatusCode');
    final marketStatus = _expectString(root, 'marketStatus');
    final generatedAt = _timestamp(root, 'generatedAt');
    _validateFreshTimestamp(generatedAt, 'generatedAt');
    _validateSafety(_object(root['safety'], 'safety'));

    if (marketStatusCode != 'demo_not_connected') {
      throw const CockpitContractException(
        'Demo responses must declare that they are not connected.',
      );
    }

    final watchlistValue = root['watchlist'];
    if (watchlistValue is! List<Object?> || watchlistValue.isEmpty) {
      throw const CockpitContractException('watchlist must be non-empty.');
    }
    if (watchlistValue.length > 100) {
      throw const CockpitContractException('watchlist is too large.');
    }

    final symbols = <String>{};
    final watchlist = <MarketQuote>[];
    for (var index = 0; index < watchlistValue.length; index++) {
      final quote = _object(watchlistValue[index], 'watchlist[$index]');
      final symbol = _expectString(quote, 'symbol');
      if (!_symbolPattern.hasMatch(symbol)) {
        throw CockpitContractException('$symbol is not a normalized symbol.');
      }
      if (!symbols.add(symbol)) {
        throw CockpitContractException('Duplicate symbol $symbol.');
      }
      final observedAt = _timestamp(quote, 'observedAt');
      if (observedAt.isAfter(generatedAt)) {
        throw CockpitContractException('$symbol observation is in the future.');
      }
      final sparklineValue = quote['sparkline'];
      if (sparklineValue is! List<Object?> ||
          sparklineValue.length < 2 ||
          sparklineValue.length > 500) {
        throw CockpitContractException('$symbol sparkline is invalid.');
      }
      final sparkline = sparklineValue
          .map(
            (entry) => _numberInRange(
              entry,
              '$symbol sparkline',
              minimum: double.minPositive,
              maximum: _maximumMoneyValue,
            ),
          )
          .toList(growable: false);

      final price = _numberInRange(
        quote['price'],
        '$symbol price',
        minimum: double.minPositive,
        maximum: _maximumMoneyValue,
      );
      final changePercent = _numberInRange(
        quote['changePercent'],
        '$symbol changePercent',
        minimum: -100,
        maximum: 1000000,
      );
      final spreadBps = _numberInRange(
        quote['spreadBps'],
        '$symbol spreadBps',
        minimum: 0,
        maximum: 10000,
      );
      watchlist.add(
        MarketQuote(
          symbol: symbol,
          displayName: _expectString(quote, 'displayName', maxLength: 120),
          price: price,
          changePercent: changePercent,
          spreadBps: spreadBps,
          freshness: _freshness(observedAt),
          sparkline: sparkline,
        ),
      );
    }

    final analysis = _parseAnalysis(_object(root['analysis'], 'analysis'));
    if (!symbols.contains(analysis.symbol)) {
      throw const CockpitContractException(
        'The analysis symbol must exist in the watchlist.',
      );
    }
    final account = _parsePaperAccount(
      _object(root['paperAccount'], 'paperAccount'),
    );

    return CockpitSnapshot(
      environment: AppEnvironment.demo,
      watchlist: List.unmodifiable(watchlist),
      analysis: analysis,
      paperAccount: account,
      marketStatus: marketStatus,
    );
  }

  void _validateSafety(Map<String, Object?> safety) {
    _expectString(safety, 'executionAuthority', allowed: const {'none'});
    for (final field in const [
      'realMoneyEnabled',
      'orderSubmissionEnabled',
      'withdrawalEnabled',
    ]) {
      if (safety[field] is! bool || safety[field] != false) {
        throw CockpitContractException('$field must be false.');
      }
    }
  }

  ExplainableAnalysis _parseAnalysis(Map<String, Object?> value) {
    final decisionText = _expectString(
      value,
      'decision',
      allowed: const {'bullish', 'bearish', 'no_trade'},
    );
    final regimeText = _expectString(
      value,
      'regime',
      allowed: const {'trending', 'ranging', 'volatile', 'uncertain'},
    );
    final confidence = _integer(
      value['confidencePercent'],
      'confidencePercent',
    );
    if (confidence < 0 || confidence > 100) {
      throw const CockpitContractException(
        'confidencePercent must be between 0 and 100.',
      );
    }
    final generatedAt = _timestamp(value, 'generatedAt');
    _validateFreshTimestamp(generatedAt, 'analysis.generatedAt');

    final factorsValue = value['factors'];
    if (factorsValue is! List<Object?> ||
        factorsValue.isEmpty ||
        factorsValue.length > 50) {
      throw const CockpitContractException('analysis factors are missing.');
    }
    final factors = <AnalysisFactor>[];
    for (var index = 0; index < factorsValue.length; index++) {
      final factor = _object(factorsValue[index], 'factors[$index]');
      _expectString(factor, 'code');
      final impactText = _expectString(
        factor,
        'impact',
        allowed: const {'supportive', 'caution', 'neutral'},
      );
      factors.add(
        AnalysisFactor(
          title: _expectString(factor, 'title'),
          detail: _expectString(factor, 'detail'),
          impact: switch (impactText) {
            'supportive' => EvidenceImpact.supportive,
            'caution' => EvidenceImpact.caution,
            _ => EvidenceImpact.neutral,
          },
        ),
      );
    }

    return ExplainableAnalysis(
      symbol: _expectString(value, 'symbol'),
      decision: switch (decisionText) {
        'bullish' => AnalysisDecision.bullish,
        'bearish' => AnalysisDecision.bearish,
        _ => AnalysisDecision.noTrade,
      },
      confidencePercent: confidence,
      regime: switch (regimeText) {
        'trending' => MarketRegime.trending,
        'ranging' => MarketRegime.ranging,
        'volatile' => MarketRegime.volatile,
        _ => MarketRegime.uncertain,
      },
      summary: _expectString(value, 'summary'),
      invalidation: _expectString(value, 'reconsiderationCondition'),
      freshness: _freshness(generatedAt),
      factors: List.unmodifiable(factors),
    );
  }

  PaperAccountSummary _parsePaperAccount(Map<String, Object?> value) {
    if (value['isSimulated'] is! bool || value['isSimulated'] != true) {
      throw const CockpitContractException(
        'The current account response must be simulated.',
      );
    }
    _expectString(value, 'currency', allowed: const {'USDT'});
    final equity = _numberInRange(
      value['equity'],
      'equity',
      minimum: 0,
      maximum: _maximumMoneyValue,
    );
    final available = _numberInRange(
      value['availableBalance'],
      'availableBalance',
      minimum: 0,
      maximum: _maximumMoneyValue,
    );
    final usedMargin = _numberInRange(
      value['usedMargin'],
      'usedMargin',
      minimum: 0,
      maximum: _maximumMoneyValue,
    );
    if ((equity - available - usedMargin).abs() > 0.000001) {
      throw const CockpitContractException(
        'Paper account balances do not reconcile.',
      );
    }
    final maximumRisk = _numberInRange(
      value['maximumDailyRiskPercent'],
      'maximumDailyRiskPercent',
      minimum: double.minPositive,
      maximum: 100,
    );
    final currentRisk = _numberInRange(
      value['currentDailyRiskPercent'],
      'currentDailyRiskPercent',
      minimum: 0,
      maximum: 100,
    );
    if (currentRisk > maximumRisk) {
      throw const CockpitContractException(
        'Current daily risk exceeds the declared maximum.',
      );
    }
    final openPositions = _integer(value['openPositions'], 'openPositions');
    if (openPositions < 0 || openPositions > 1000) {
      throw const CockpitContractException('openPositions is out of range.');
    }

    return PaperAccountSummary(
      equity: equity,
      availableBalance: available,
      usedMargin: usedMargin,
      dailyPnl: _numberInRange(
        value['dailyPnl'],
        'dailyPnl',
        minimum: -_maximumMoneyValue,
        maximum: _maximumMoneyValue,
      ),
      openPositions: openPositions,
      maximumDailyRiskPercent: maximumRisk,
      currentDailyRiskPercent: currentRisk,
    );
  }

  void _validateFreshTimestamp(DateTime value, String field) {
    if (value.isAfter(now.add(const Duration(seconds: 30)))) {
      throw CockpitContractException('$field is in the future.');
    }
    if (now.difference(value) > const Duration(minutes: 5)) {
      throw CockpitContractException('$field is stale.');
    }
  }

  Duration _freshness(DateTime value) {
    final difference = now.difference(value);
    return difference.isNegative ? Duration.zero : difference;
  }

  static Map<String, Object?> _object(Object? value, String field) {
    if (value is! Map<String, Object?>) {
      throw CockpitContractException('$field must be an object.');
    }
    return value;
  }

  static String _expectString(
    Map<String, Object?> object,
    String field, {
    Set<String>? allowed,
    int maxLength = 4096,
  }) {
    final value = object[field];
    if (value is! String || value.trim().isEmpty || value.length > maxLength) {
      throw CockpitContractException('$field must be a non-empty string.');
    }
    if (allowed != null && !allowed.contains(value)) {
      throw CockpitContractException('$field has an unsupported value.');
    }
    return value;
  }

  static DateTime _timestamp(Map<String, Object?> object, String field) {
    final value = _expectString(object, field);
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc) {
      throw CockpitContractException(
        '$field must be an explicit UTC timestamp.',
      );
    }
    return parsed;
  }

  static double _finiteNumber(Object? value, String field) {
    if (value is! num) {
      throw CockpitContractException('$field must be numeric.');
    }
    final number = value.toDouble();
    if (!number.isFinite) {
      throw CockpitContractException('$field must be finite.');
    }
    return number;
  }

  static double _numberInRange(
    Object? value,
    String field, {
    required double minimum,
    required double maximum,
  }) {
    final number = _finiteNumber(value, field);
    if (number < minimum || number > maximum) {
      throw CockpitContractException('$field is out of range.');
    }
    return number;
  }

  static int _integer(Object? value, String field) {
    if (value is! int) {
      throw CockpitContractException('$field must be an integer.');
    }
    return value;
  }
}
