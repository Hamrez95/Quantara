enum TraderAgentSeverity { info, warning, p2, p1, p0 }

enum TraderAgentFeature {
  onboarding,
  radar,
  setups,
  analysis,
  watchlist,
  strategyLab,
  profile,
  background,
  notifications,
  autoTrade,
  persistence,
  accessibility,
  safety,
}

enum TraderAgentStepStatus { passed, failed, skipped }

enum TraderAgentNetworkProfile { normal, slow, intermittent, offline }

final class TraderAgentPersona {
  const TraderAgentPersona({
    required this.id,
    required this.displayName,
    required this.role,
    required this.languageCode,
    required this.darkMode,
    required this.textScale,
    required this.capital,
    required this.riskPercent,
    required this.symbols,
    required this.timeframes,
    required this.focus,
  });

  final String id;
  final String displayName;
  final String role;
  final String languageCode;
  final bool darkMode;
  final double textScale;
  final double capital;
  final double riskPercent;
  final List<String> symbols;
  final List<String> timeframes;
  final Set<TraderAgentFeature> focus;

  static const builtIn = <TraderAgentPersona>[
    TraderAgentPersona(
      id: 'arman-conservative-swing',
      displayName: 'Arman',
      role: 'Conservative Swing Trader',
      languageCode: 'fa',
      darkMode: true,
      textScale: 1,
      capital: 800,
      riskPercent: 0.5,
      symbols: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT'],
      timeframes: ['1h', '4h'],
      focus: {
        TraderAgentFeature.radar,
        TraderAgentFeature.setups,
        TraderAgentFeature.analysis,
        TraderAgentFeature.safety,
      },
    ),
    TraderAgentPersona(
      id: 'nima-active-scalper',
      displayName: 'Nima',
      role: 'Active Scalper',
      languageCode: 'fa',
      darkMode: true,
      textScale: 1,
      capital: 2500,
      riskPercent: 1,
      symbols: ['BTCUSDT', 'ETHUSDT', 'XRPUSDT', 'AVAXUSDT'],
      timeframes: ['15m', '1h'],
      focus: {
        TraderAgentFeature.radar,
        TraderAgentFeature.analysis,
        TraderAgentFeature.watchlist,
        TraderAgentFeature.background,
        TraderAgentFeature.notifications,
      },
    ),
    TraderAgentPersona(
      id: 'sara-risk-manager',
      displayName: 'Sara',
      role: 'Risk Manager',
      languageCode: 'en',
      darkMode: false,
      textScale: 1,
      capital: 10000,
      riskPercent: 1,
      symbols: ['BTCUSDT', 'ETHUSDT'],
      timeframes: ['1h', '4h'],
      focus: {
        TraderAgentFeature.profile,
        TraderAgentFeature.setups,
        TraderAgentFeature.safety,
        TraderAgentFeature.persistence,
      },
    ),
    TraderAgentPersona(
      id: 'kian-bitunix-operator',
      displayName: 'Kian',
      role: 'Bitunix Operator',
      languageCode: 'fa',
      darkMode: false,
      textScale: 1,
      capital: 5000,
      riskPercent: 0.75,
      symbols: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT'],
      timeframes: ['15m', '1h', '4h'],
      focus: {
        TraderAgentFeature.autoTrade,
        TraderAgentFeature.persistence,
        TraderAgentFeature.safety,
      },
    ),
    TraderAgentPersona(
      id: 'mina-accessibility-rtl',
      displayName: 'Mina',
      role: 'Accessibility and RTL Auditor',
      languageCode: 'fa',
      darkMode: false,
      textScale: 1.6,
      capital: 800,
      riskPercent: 0.5,
      symbols: ['BTCUSDT', 'XRPUSDT'],
      timeframes: ['15m', '4h'],
      focus: {
        TraderAgentFeature.accessibility,
        TraderAgentFeature.onboarding,
        TraderAgentFeature.analysis,
        TraderAgentFeature.setups,
      },
    ),
    TraderAgentPersona(
      id: 'reza-chaos-trader',
      displayName: 'Reza',
      role: 'Chaos Trader',
      languageCode: 'en',
      darkMode: true,
      textScale: 1.3,
      capital: 1200,
      riskPercent: 1.5,
      symbols: ['BTCUSDT', 'ETHUSDT', 'AVAXUSDT', 'SOLUSDT'],
      timeframes: ['15m', '1h', '4h'],
      focus: {
        TraderAgentFeature.background,
        TraderAgentFeature.persistence,
        TraderAgentFeature.autoTrade,
        TraderAgentFeature.safety,
      },
    ),
    TraderAgentPersona(
      id: 'leila-strategy-researcher',
      displayName: 'Leila',
      role: 'Strategy Researcher',
      languageCode: 'fa',
      darkMode: true,
      textScale: 1,
      capital: 3000,
      riskPercent: 0.75,
      symbols: ['BTCUSDT', 'ETHUSDT', 'XRPUSDT'],
      timeframes: ['15m', '1h', '4h'],
      focus: {
        TraderAgentFeature.strategyLab,
        TraderAgentFeature.analysis,
        TraderAgentFeature.setups,
        TraderAgentFeature.persistence,
      },
    ),
    TraderAgentPersona(
      id: 'omid-execution-auditor',
      displayName: 'Omid',
      role: 'Execution Auditor',
      languageCode: 'en',
      darkMode: false,
      textScale: 1,
      capital: 1000,
      riskPercent: 0.25,
      symbols: ['BTCUSDT'],
      timeframes: ['1h'],
      focus: {
        TraderAgentFeature.autoTrade,
        TraderAgentFeature.safety,
        TraderAgentFeature.persistence,
      },
    ),
  ];
}

final class TraderAgentStepResult {
  const TraderAgentStepResult({
    required this.id,
    required this.feature,
    required this.status,
    required this.elapsed,
    this.message,
  });

  final String id;
  final TraderAgentFeature feature;
  final TraderAgentStepStatus status;
  final Duration elapsed;
  final String? message;
}

final class TraderAgentFinding {
  const TraderAgentFinding({
    required this.personaId,
    required this.stepId,
    required this.feature,
    required this.severity,
    required this.title,
    required this.details,
    required this.seed,
  });

  final String personaId;
  final String stepId;
  final TraderAgentFeature feature;
  final TraderAgentSeverity severity;
  final String title;
  final String details;
  final int seed;

  bool get blocksRelease =>
      severity == TraderAgentSeverity.p0 || severity == TraderAgentSeverity.p1;
}

final class TraderAgentRunReport {
  const TraderAgentRunReport({
    required this.persona,
    required this.seed,
    required this.startedAt,
    required this.finishedAt,
    required this.steps,
    required this.findings,
  });

  final TraderAgentPersona persona;
  final int seed;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<TraderAgentStepResult> steps;
  final List<TraderAgentFinding> findings;

  bool get passed => findings.every((finding) => !finding.blocksRelease);

  Set<TraderAgentFeature> get coveredFeatures =>
      steps.map((step) => step.feature).toSet();
}
