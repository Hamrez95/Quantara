import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trader_agent_lab/application/trader_agent_lab.dart';
import 'package:quantara_app/features/trader_agent_lab/domain/trader_agent_models.dart';

void main() {
  test('all built-in trader personas complete the healthy deterministic probe', () async {
    final lab = TraderAgentLab();
    final reports = await lab.runAll(
      seed: 42,
      probeFactory: (_) => _FakeTraderAgentProbe(),
    );

    expect(reports, hasLength(TraderAgentPersona.builtIn.length));
    expect(reports.every((report) => report.passed), isTrue);
    expect(
      reports.expand((report) => report.coveredFeatures),
      containsAll({
        TraderAgentFeature.analysis,
        TraderAgentFeature.setups,
        TraderAgentFeature.safety,
        TraderAgentFeature.autoTrade,
        TraderAgentFeature.accessibility,
        TraderAgentFeature.strategyLab,
      }),
    );
    expect(
      reports.map((report) => report.seed),
      orderedEquals(List.generate(reports.length, (index) => 42 + index * 997)),
    );
  });

  test('stale sizing capital is reported as a P1 release blocker', () async {
    final persona = TraderAgentPersona.builtIn.first;
    final report = await TraderAgentLab().runPersona(
      persona: persona,
      probe: _FakeTraderAgentProbe(capitalOffset: 9200),
      seed: 7,
    );

    expect(report.passed, isFalse);
    expect(
      report.findings,
      contains(
        isA<TraderAgentFinding>()
            .having((finding) => finding.severity, 'severity', TraderAgentSeverity.p1)
            .having(
              (finding) => finding.title,
              'title',
              'Sizing capital did not propagate',
            ),
      ),
    );
  });

  test('layout overflow or endless scroll becomes a P0 blocker', () async {
    final persona = TraderAgentPersona.builtIn.firstWhere(
      (item) => item.focus.contains(TraderAgentFeature.accessibility),
    );
    final report = await TraderAgentLab().runPersona(
      persona: persona,
      probe: _FakeTraderAgentProbe(
        layoutOverflowCount: 1,
        endlessScrollDetected: true,
      ),
      seed: 9,
    );

    expect(report.passed, isFalse);
    expect(
      report.findings.any(
        (finding) =>
            finding.severity == TraderAgentSeverity.p0 &&
            finding.title == 'Layout or infinite-scroll regression detected',
      ),
      isTrue,
    );
  });

  test('premature live or withdrawal authority becomes a P0 blocker', () async {
    final persona = TraderAgentPersona.builtIn.firstWhere(
      (item) => item.focus.contains(TraderAgentFeature.autoTrade),
    );
    final report = await TraderAgentLab().runPersona(
      persona: persona,
      probe: _FakeTraderAgentProbe(
        liveTradingEnabled: true,
        withdrawalEnabled: true,
      ),
      seed: 11,
    );

    expect(report.passed, isFalse);
    expect(
      report.findings.any(
        (finding) =>
            finding.severity == TraderAgentSeverity.p0 &&
            finding.title == 'Unsafe exchange authority detected',
      ),
      isTrue,
    );
  });
}

final class _FakeTraderAgentProbe implements TraderAgentProbe {
  _FakeTraderAgentProbe({
    this.capitalOffset = 0,
    this.layoutOverflowCount = 0,
    this.endlessScrollDetected = false,
    this.liveTradingEnabled = false,
    this.withdrawalEnabled = false,
  });

  final double capitalOffset;
  final int layoutOverflowCount;
  final bool endlessScrollDetected;
  final bool liveTradingEnabled;
  final bool withdrawalEnabled;

  double _capital = 10000;
  double _riskPercent = 1;
  int _leverage = 1;
  String _symbol = 'BTCUSDT';
  String _timeframe = '1h';
  bool _autoTradeReadOnly = false;
  TraderAgentNetworkProfile _network = TraderAgentNetworkProfile.normal;

  @override
  Future<void> reset({required int seed}) async {
    _capital = 10000;
    _riskPercent = 1;
    _leverage = 1;
    _symbol = 'BTCUSDT';
    _timeframe = '1h';
    _autoTradeReadOnly = false;
    _network = TraderAgentNetworkProfile.normal;
  }

  @override
  Future<void> configure(TraderAgentPersona persona) async {
    _capital = persona.capital;
    _riskPercent = persona.riskPercent;
    _symbol = persona.symbols.first;
    _timeframe = persona.timeframes.first;
  }

  @override
  Future<void> openFeature(TraderAgentFeature feature) async {}

  @override
  Future<void> setCapital(double capital) async {
    _capital = capital + capitalOffset;
  }

  @override
  Future<void> setRiskPercent(double riskPercent) async {
    _riskPercent = riskPercent;
  }

  @override
  Future<void> setLeverage(int leverage) async {
    _leverage = leverage;
  }

  @override
  Future<void> selectMarket({
    required String symbol,
    required String timeframe,
  }) async {
    _symbol = symbol;
    _timeframe = timeframe;
  }

  @override
  Future<void> setNetworkProfile(TraderAgentNetworkProfile profile) async {
    _network = profile;
  }

  @override
  Future<void> backgroundAndResume() async {
    if (_network == TraderAgentNetworkProfile.offline) {
      return;
    }
  }

  @override
  Future<void> restart() async {}

  @override
  Future<void> connectAutoTradeReadOnly() async {
    _autoTradeReadOnly = true;
  }

  @override
  Future<void> rapidNavigate({required int iterations}) async {
    expect(iterations, greaterThanOrEqualTo(100));
  }

  @override
  Future<TraderAgentProbeSnapshot> snapshot() async => TraderAgentProbeSnapshot(
    capital: _capital,
    riskPercent: _riskPercent,
    selectedLeverage: _leverage,
    selectedSymbol: _symbol,
    selectedTimeframe: _timeframe,
    liveTradingEnabled: liveTradingEnabled,
    withdrawalEnabled: withdrawalEnabled,
    autoTradeReadOnly: _autoTradeReadOnly,
    unhandledErrorCount: 0,
    layoutOverflowCount: layoutOverflowCount,
    endlessScrollDetected: endlessScrollDetected,
    staleExecutablePlanDetected: false,
  );
}
