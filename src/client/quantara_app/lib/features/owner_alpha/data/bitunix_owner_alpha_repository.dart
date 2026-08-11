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
  static const supportedTimeframes = ['5m', '15m', '30m', '1h', '4h', '1D'];
  static const opportunityTimeframes = ['5m', '15m', '30m', '1h', '4h'];
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
  final Map<String, TimeframeChartAnalysis> _analysisCache = {};

  @override
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  }) async {
    final stopwatch = Stopwatch()..start();
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
      final requests = <(String, String)>[
        for (final symbol in normalized)
          for (final timeframe in opportunityTimeframes) (symbol, timeframe),
        (selected, '1D'),
      ];
      final analysesBySymbol = <String, Map<String, TimeframeChartAnalysis>>{};
      final failures = <String, String>{};
      final pendingRequests = <(String, String)>[];
      var cacheHits = 0;
      for (final request in requests) {
        final cached = _freshCachedAnalysis(request.$1, request.$2);
        if (cached == null) {
          pendingRequests.add(request);
        } else {
          cacheHits++;
          (analysesBySymbol[request.$1] ??= {})[request.$2] = cached;
        }
      }
      for (var offset = 0; offset < pendingRequests.length; offset += 4) {
        final end = math.min(offset + 4, pendingRequests.length);
        final batch = pendingRequests.sublist(offset, end);
        final results = await Future.wait(
          batch.map(
            (request) => _tryLoadAnalysis(request.$1, request.$2, languageCode),
          ),
        );
        for (final result in results) {
          final analysis = result.analysis;
          if (analysis != null) {
            _analysisCache[_cacheKey(result.symbol, result.timeframe)] =
                analysis;
            (analysesBySymbol[result.symbol] ??= {})[result.timeframe] =
                analysis;
          } else {
            failures['${result.symbol}/${result.timeframe}'] =
                result.errorMessage!;
          }
        }
        await _pace();
      }

      final radar = <SymbolRadarResult>[];
      for (final symbol in normalized) {
        final analyses = analysesBySymbol[symbol];
        if (analyses == null || analyses.isEmpty) {
          continue;
        }
        final analysis =
            analyses['1h'] ??
            analyses['30m'] ??
            analyses['15m'] ??
            analyses['5m'] ??
            analyses['4h'] ??
            analyses.values.first;
        final symbolDirections = <String, ChartDirection>{
          for (final entry in analyses.entries)
            entry.key: entry.value.direction,
        };
        final ideas = <String, TradeIdea>{
          for (final entry in analyses.entries)
            if (opportunityTimeframes.contains(entry.key))
              entry.key: TradeIdeaFactory.create(
                analysis: entry.value,
                capital: capital,
                riskPercent: riskPercent,
                languageCode: languageCode,
                confluence: symbolDirections,
              ),
        };
        radar.add(
          SymbolRadarResult(
            quote: quotes[symbol]!,
            analysis: analysis,
            idea:
                ideas[analysis.timeframe] ??
                TradeIdeaFactory.create(
                  analysis: analysis,
                  capital: capital,
                  riskPercent: riskPercent,
                  languageCode: languageCode,
                  confluence: symbolDirections,
                ),
            analysesByTimeframe: analyses,
            ideasByTimeframe: ideas,
          ),
        );
      }
      if (radar.isEmpty) {
        throw OwnerAlphaDataException(
          'هیچ‌کدام از نمادها داده کافی و معتبر برای تحلیل نداشتند.',
          'None of the symbols had enough valid data for analysis.',
        );
      }
      final effectiveSelected =
          radar.any((result) => result.quote.symbol == selected)
          ? selected
          : radar.first.quote.symbol;
      final selectedResult = radar.firstWhere(
        (result) => result.quote.symbol == effectiveSelected,
      );
      final selectedAnalysis =
          selectedResult.analysesByTimeframe[selectedTimeframe] ??
          selectedResult.analysis;
      final directions = <String, ChartDirection>{
        for (final entry in selectedResult.analysesByTimeframe.entries)
          entry.key: entry.value.direction,
      };
      final rejections = <SetupRejectionReason, int>{};
      for (final result in radar) {
        for (final idea in result.ideasByTimeframe.values) {
          if (idea.rejectionReason != SetupRejectionReason.none) {
            rejections.update(
              idea.rejectionReason,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }
        }
      }
      if (failures.isNotEmpty) {
        rejections[SetupRejectionReason.dataUnavailable] = failures.length;
      }
      stopwatch.stop();
      return OwnerAlphaSnapshot(
        radar: radar,
        selectedSymbol: effectiveSelected,
        selectedTimeframe: selectedAnalysis.timeframe,
        selectedAnalysis: selectedAnalysis,
        selectedIdea: TradeIdeaFactory.create(
          analysis: selectedAnalysis,
          capital: capital,
          riskPercent: riskPercent,
          languageCode: languageCode,
          confluence: directions,
        ),
        timeframeDirections: directions,
        scanFailures: failures,
        diagnostics: ScanDiagnostics(
          elapsed: stopwatch.elapsed,
          networkRequests: pendingRequests.length + 1,
          cacheHits: cacheHits,
          requestedAnalyses: requests.length,
          rejections: rejections,
        ),
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

  TimeframeChartAnalysis? _freshCachedAnalysis(
    String symbol,
    String timeframe,
  ) {
    final cached = _analysisCache[_cacheKey(symbol, timeframe)];
    if (cached == null) {
      return null;
    }
    final nextClosedCandleAt = cached.latestCandle.openTime.add(
      _durationFor(timeframe) * 2,
    );
    if (!_now().toUtc().isBefore(nextClosedCandleAt)) {
      _analysisCache.remove(_cacheKey(symbol, timeframe));
      return null;
    }
    return cached;
  }

  static String _cacheKey(String symbol, String timeframe) =>
      '$symbol/$timeframe';

  Future<_AnalysisLoadResult> _tryLoadAnalysis(
    String symbol,
    String timeframe,
    String languageCode,
  ) async {
    try {
      return _AnalysisLoadResult(
        symbol: symbol,
        timeframe: timeframe,
        analysis: await _loadAnalysis(symbol, timeframe),
      );
    } on OwnerAlphaDataException catch (error) {
      return _AnalysisLoadResult(
        symbol: symbol,
        timeframe: timeframe,
        errorMessage: error.messageFor(languageCode),
      );
    } on TimeoutException {
      return _AnalysisLoadResult(
        symbol: symbol,
        timeframe: timeframe,
        errorMessage: languageCode == 'en'
            ? 'Timed out while loading this timeframe.'
            : 'دریافت این تایم‌فریم بیش از حد طول کشید.',
      );
    } on Object {
      return _AnalysisLoadResult(
        symbol: symbol,
        timeframe: timeframe,
        errorMessage: languageCode == 'en'
            ? 'This timeframe returned incompatible market data.'
            : 'داده این تایم‌فریم با قرارداد مورد انتظار سازگار نبود.',
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
        'limit': '200',
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
      final openValue = item['open'];
      final highValue = item['high'];
      final lowValue = item['low'];
      final closeValue = item['close'];
      final open = _positiveNumber(openValue);
      final rawHigh = _positiveNumber(highValue);
      final rawLow = _positiveNumber(lowValue);
      final close = _positiveNumber(closeValue);
      final bodyHigh = math.max(open, close);
      final bodyLow = math.min(open, close);
      final priceQuantum = [
        _decimalQuantum(openValue),
        _decimalQuantum(highValue),
        _decimalQuantum(lowValue),
        _decimalQuantum(closeValue),
      ].reduce(math.max);
      final roundingTolerance = math.max(bodyHigh * 0.0001, priceQuantum * 1.1);
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
      '5m' => const Duration(minutes: 5),
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

  static double _decimalQuantum(Object? value) {
    final text = value.toString().toLowerCase();
    if (text.contains('e')) {
      return 0;
    }
    final separator = text.indexOf('.');
    if (separator < 0) {
      return 1;
    }
    final decimals = text.length - separator - 1;
    return math.pow(10, -decimals).toDouble();
  }
}

final class _AnalysisLoadResult {
  const _AnalysisLoadResult({
    required this.symbol,
    required this.timeframe,
    this.analysis,
    this.errorMessage,
  }) : assert(
         (analysis == null) != (errorMessage == null),
         'Exactly one result value is required.',
       );

  final String symbol;
  final String timeframe;
  final TimeframeChartAnalysis? analysis;
  final String? errorMessage;
}
