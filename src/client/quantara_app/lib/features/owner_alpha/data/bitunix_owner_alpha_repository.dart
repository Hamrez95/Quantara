import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../market_analysis/data/chart_structure_analyzer.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/owner_alpha_models.dart';
import 'trade_idea_factory.dart';

final class OwnerAlphaDataException implements Exception {
  const OwnerAlphaDataException(this.persianMessage, this.englishMessage);

  final String persianMessage;
  final String englishMessage;

  String messageFor(String languageCode) =>
      languageCode == 'en' ? englishMessage : persianMessage;

  @override
  String toString() => persianMessage;
}

final class BitunixOwnerAlphaRepository implements OwnerAlphaRepository {
  factory BitunixOwnerAlphaRepository({
    required http.Client client,
    Duration timeout = const Duration(seconds: 10),
    Duration requestSpacing = const Duration(milliseconds: 120),
    DateTime Function()? now,
  }) {
    return BitunixOwnerAlphaRepository._(
      client,
      timeout,
      requestSpacing,
      now ?? DateTime.now,
    );
  }

  BitunixOwnerAlphaRepository._(
    this._client,
    this._timeout,
    this._requestSpacing,
    this._now,
  ) {
    if (_timeout <= Duration.zero || _timeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(_timeout, 'timeout');
    }
    if (_requestSpacing.isNegative) {
      throw ArgumentError.value(_requestSpacing, 'requestSpacing');
    }
  }

  static final _symbolPattern = RegExp(r'^[A-Z0-9]{5,24}$');
  static const _apiOrigin = 'https://fapi.bitunix.com';
  static const _maximumResponseBytes = 2 * 1024 * 1024;
  static const supportedTimeframes = ['15m', '1h', '4h', '1D'];
  static const _displayNames = {
    'BTCUSDT': 'Bitcoin',
    'ETHUSDT': 'Ethereum',
    'SOLUSDT': 'Solana',
    'AVAXUSDT': 'Avalanche',
    'BNBUSDT': 'BNB',
    'XRPUSDT': 'XRP',
    'ADAUSDT': 'Cardano',
    'DOGEUSDT': 'Dogecoin',
    'PAXGUSDT': 'PAX Gold',
  };

  final http.Client _client;
  final Duration _timeout;
  final Duration _requestSpacing;
  final DateTime Function() _now;

  @override
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  }) async {
    final normalized = _normalizeSymbols(symbols);
    final selected = selectedSymbol.trim().toUpperCase();
    if (!normalized.contains(selected)) {
      throw const OwnerAlphaDataException(
        'نماد انتخاب‌شده باید داخل واچ‌لیست باشد.',
        'The selected symbol must be in the watchlist.',
      );
    }
    if (!supportedTimeframes.contains(selectedTimeframe)) {
      throw const OwnerAlphaDataException(
        'تایم‌فریم انتخاب‌شده پشتیبانی نمی‌شود.',
        'The selected timeframe is not supported.',
      );
    }

    try {
      final quotes = await _loadQuotes(normalized);
      final hourlyAnalyses = <String, TimeframeChartAnalysis>{};
      for (final symbol in normalized) {
        hourlyAnalyses[symbol] = await _loadAnalysis(symbol, '1h');
        await _pace();
      }

      final selectedAnalyses = <String, TimeframeChartAnalysis>{
        '1h': hourlyAnalyses[selected]!,
      };
      for (final timeframe in supportedTimeframes) {
        if (timeframe == '1h') {
          continue;
        }
        selectedAnalyses[timeframe] = await _loadAnalysis(selected, timeframe);
        await _pace();
      }

      final directions = <String, ChartDirection>{
        for (final entry in selectedAnalyses.entries)
          entry.key: entry.value.direction,
      };
      final radar = <SymbolRadarResult>[];
      for (final symbol in normalized) {
        final analysis = hourlyAnalyses[symbol]!;
        radar.add(
          SymbolRadarResult(
            quote: quotes[symbol]!,
            analysis: analysis,
            idea: TradeIdeaFactory.create(
              analysis: analysis,
              capital: capital,
              riskPercent: riskPercent,
              languageCode: languageCode,
              confluence: symbol == selected ? directions : const {},
            ),
          ),
        );
      }

      final selectedAnalysis = selectedAnalyses[selectedTimeframe]!;
      return OwnerAlphaSnapshot(
        radar: radar,
        selectedSymbol: selected,
        selectedTimeframe: selectedTimeframe,
        selectedAnalysis: selectedAnalysis,
        selectedIdea: TradeIdeaFactory.create(
          analysis: selectedAnalysis,
          capital: capital,
          riskPercent: riskPercent,
          languageCode: languageCode,
          confluence: directions,
        ),
        timeframeDirections: directions,
        generatedAt: _now().toUtc(),
      );
    } on OwnerAlphaDataException {
      rethrow;
    } on TimeoutException {
      throw const OwnerAlphaDataException(
        'پاسخ Bitunix دیر رسید. اتصال اینترنت را بررسی کنید.',
        'Bitunix took too long to respond. Check your internet connection.',
      );
    } on http.ClientException {
      throw const OwnerAlphaDataException(
        'اتصال امن به داده عمومی Bitunix برقرار نشد.',
        'A secure connection to public Bitunix data could not be established.',
      );
    } on FormatException {
      throw const OwnerAlphaDataException(
        'پاسخ بازار با قرارداد مورد انتظار Quantara سازگار نبود.',
        'The market response did not match Quantara\'s expected contract.',
      );
    }
  }

  Future<Map<String, AlphaMarketQuote>> _loadQuotes(
    List<String> symbols,
  ) async {
    final uri = Uri.parse(
      '$_apiOrigin/api/v1/futures/market/tickers',
    ).replace(queryParameters: {'symbols': symbols.join(',')});
    final root = await _getJson(uri);
    final data = root['data'];
    if (data is! List<Object?>) {
      throw const FormatException('Ticker data must be a list.');
    }

    final observedAt = _now().toUtc();
    final result = <String, AlphaMarketQuote>{};
    for (final value in data) {
      final item = _object(value);
      final symbol = _string(item['symbol']).toUpperCase();
      if (!symbols.contains(symbol) || result.containsKey(symbol)) {
        continue;
      }
      final last = _positiveNumber(item['lastPrice'] ?? item['last']);
      final open = _positiveNumber(item['open']);
      final high = _positiveNumber(item['high']);
      final low = _positiveNumber(item['low']);
      if (high < low || last > high * 1.2 || last < low * 0.8) {
        throw FormatException('Invalid ticker range for $symbol.');
      }
      result[symbol] = AlphaMarketQuote(
        symbol: symbol,
        displayName: _displayNames[symbol] ?? symbol.replaceAll('USDT', ''),
        lastPrice: last,
        changePercent: (last - open) / open * 100,
        high24h: high,
        low24h: low,
        observedAt: observedAt,
      );
    }
    final missing = symbols.where((symbol) => !result.containsKey(symbol));
    if (missing.isNotEmpty) {
      throw OwnerAlphaDataException(
        'نماد ${missing.join('، ')} در بازار Futures بیتیونیکس پیدا نشد.',
        '${missing.join(', ')} was not found in the Bitunix Futures market.',
      );
    }
    return result;
  }

  Future<TimeframeChartAnalysis> _loadAnalysis(
    String symbol,
    String timeframe,
  ) async {
    final uri = Uri.parse('$_apiOrigin/api/v1/futures/market/kline').replace(
      queryParameters: {
        'symbol': symbol,
        'interval': timeframe == '1D' ? '1d' : timeframe,
        'limit': '120',
        'type': 'LAST_PRICE',
      },
    );
    final root = await _getJson(uri);
    final data = root['data'];
    if (data is! List<Object?>) {
      throw const FormatException('Kline data must be a list.');
    }

    final byTime = <int, ChartCandle>{};
    final now = _now().toUtc();
    final interval = _durationFor(timeframe);
    for (final value in data) {
      final item = _object(value);
      final epoch = _integer(item['time']);
      final openTime = DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
      if (openTime.isBefore(DateTime.utc(2020)) ||
          openTime.isAfter(now.add(const Duration(days: 1)))) {
        throw FormatException('Invalid candle time for $symbol/$timeframe.');
      }
      final open = _positiveNumber(item['open']);
      final rawHigh = _positiveNumber(item['high']);
      final rawLow = _positiveNumber(item['low']);
      final close = _positiveNumber(item['close']);
      final bodyHigh = math.max(open, close);
      final bodyLow = math.min(open, close);
      final roundingTolerance = bodyHigh * 0.0001;
      if (bodyHigh - rawHigh > roundingTolerance ||
          rawLow - bodyLow > roundingTolerance) {
        throw FormatException('Invalid candle range for $symbol/$timeframe.');
      }
      final candle = ChartCandle(
        openTime: openTime,
        open: open,
        high: math.max(rawHigh, bodyHigh),
        low: math.min(rawLow, bodyLow),
        close: close,
        volume: _nonNegativeNumber(item['baseVol'] ?? item['quoteVol']),
      );
      if (!candle.isValid) {
        throw FormatException('Invalid candle for $symbol/$timeframe.');
      }
      if (!openTime.add(interval).isAfter(now)) {
        byTime[epoch] = candle;
      }
    }
    final candles = byTime.values.toList(growable: false)
      ..sort((left, right) => left.openTime.compareTo(right.openTime));
    if (candles.length < 30) {
      throw OwnerAlphaDataException(
        'داده کافی برای تحلیل $symbol در بازه $timeframe وجود ندارد.',
        'There is not enough $symbol data for $timeframe analysis.',
      );
    }
    final lastClosedAt = candles.last.openTime.add(interval);
    if (now.difference(lastClosedAt) > interval * 3) {
      throw OwnerAlphaDataException(
        'آخرین کندل کامل $symbol در بازه $timeframe قدیمی است.',
        'The latest closed $symbol candle for $timeframe is stale.',
      );
    }

    final structure = ChartStructureAnalyzer.analyze(candles);
    final generatedAt = _now().toUtc();
    final directionText = switch (structure.direction) {
      ChartDirection.bullish => 'صعودی',
      ChartDirection.bearish => 'نزولی',
      ChartDirection.sideways => 'خنثی',
    };
    return TimeframeChartAnalysis(
      symbol: symbol,
      timeframe: timeframe,
      candles: candles,
      zones: structure.zones,
      direction: structure.direction,
      directionStrength: structure.directionStrength,
      volatilityPercent: structure.volatilityPercent,
      summary:
          'ساختار $timeframe $directionText است؛ ${(structure.directionStrength * 100).round()}٪ قدرت و ${structure.zones.length} ناحیه تأییدشده دارد.',
      generatedAt: generatedAt,
      fingerprint:
          '$symbol-$timeframe-${candles.first.openTime.millisecondsSinceEpoch}-${candles.last.openTime.millisecondsSinceEpoch}-${candles.last.close}',
    );
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != 'fapi.bitunix.com') {
      throw const OwnerAlphaDataException(
        'مقصد داده بازار معتبر نیست.',
        'The market data destination is not trusted.',
      );
    }
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(_timeout);
    if (response.statusCode == 429) {
      throw const OwnerAlphaDataException(
        'محدودیت موقت درخواست Bitunix فعال شده؛ کمی بعد دوباره تلاش کنید.',
        'Bitunix is temporarily rate limiting requests. Try again shortly.',
      );
    }
    if (response.statusCode != 200) {
      throw OwnerAlphaDataException(
        'Bitunix پاسخ ${response.statusCode} برگرداند.',
        'Bitunix returned status ${response.statusCode}.',
      );
    }
    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType != 'application/json') {
      throw const FormatException('Expected application/json response.');
    }
    if (response.bodyBytes.length > _maximumResponseBytes) {
      throw const FormatException('Response is too large.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final root = _object(decoded);
    if (_integer(root['code']) != 0) {
      throw OwnerAlphaDataException(
        'Bitunix درخواست را نپذیرفت: ${_string(root['msg'])}',
        'Bitunix rejected the request: ${_string(root['msg'])}',
      );
    }
    return root;
  }

  static Duration _durationFor(String timeframe) {
    return switch (timeframe) {
      '15m' => const Duration(minutes: 15),
      '1h' => const Duration(hours: 1),
      '4h' => const Duration(hours: 4),
      '1D' => const Duration(days: 1),
      _ => throw const FormatException('Unsupported timeframe.'),
    };
  }

  Future<void> _pace() async {
    if (_requestSpacing > Duration.zero) {
      await Future<void>.delayed(_requestSpacing);
    }
  }

  static List<String> _normalizeSymbols(List<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final symbol = value.trim().toUpperCase();
      if (!_symbolPattern.hasMatch(symbol)) {
        throw OwnerAlphaDataException(
          'نماد «$value» معتبر نیست.',
          'The symbol “$value” is invalid.',
        );
      }
      if (seen.add(symbol)) {
        result.add(symbol);
      }
    }
    if (result.isEmpty || result.length > 12) {
      throw const OwnerAlphaDataException(
        'واچ‌لیست باید بین ۱ تا ۱۲ نماد داشته باشد.',
        'The watchlist must contain between 1 and 12 symbols.',
      );
    }
    return result;
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Expected JSON object.');
    }
    return value;
  }

  static String _string(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 160) {
      throw const FormatException('Expected bounded string.');
    }
    return value.trim();
  }

  static int _integer(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw const FormatException('Expected integer.');
  }

  static double _positiveNumber(Object? value) {
    final number = _number(value);
    if (number <= 0) {
      throw const FormatException('Expected positive number.');
    }
    return number;
  }

  static double _nonNegativeNumber(Object? value) {
    final number = _number(value);
    if (number < 0) {
      throw const FormatException('Expected non-negative number.');
    }
    return number;
  }

  static double _number(Object? value) {
    final number = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
    if (number == null || !number.isFinite || number.abs() > 1e18) {
      throw const FormatException('Expected finite number.');
    }
    return number;
  }
}
