import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/owner_alpha_models.dart';
import 'professional_strategy_engine.dart';

enum StrategyLifecycle {
  active,
  disabledForNewRuns,
  deprecated,
  removedFromRuntime,
}

final class StrategySnapshotIdentity {
  const StrategySnapshotIdentity({
    required this.strategyId,
    required this.strategyVersion,
    required this.parameterSchemaVersion,
    required this.normalizedParameters,
    required this.snapshotHash,
    required this.managementPolicyVersion,
    required this.implementationVersion,
    required this.lifecycle,
  });

  final String strategyId;
  final String strategyVersion;
  final int parameterSchemaVersion;
  final Map<String, Object?> normalizedParameters;
  final String snapshotHash;
  final String managementPolicyVersion;
  final String implementationVersion;
  final StrategyLifecycle lifecycle;

  Map<String, Object?> toJson() => <String, Object?>{
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'parameterSchemaVersion': parameterSchemaVersion,
    'normalizedParameters': normalizedParameters,
    'snapshotHash': snapshotHash,
    'managementPolicyVersion': managementPolicyVersion,
    'implementationVersion': implementationVersion,
    'lifecycle': lifecycle.name,
  };

  static StrategySnapshotIdentity? tryFromJson(Map<String, Object?> value) {
    try {
      final strategyId = value['strategyId'] as String;
      final strategyVersion = value['strategyVersion'] as String;
      final parameterSchemaVersion = value['parameterSchemaVersion'] as int;
      final snapshotHash = value['snapshotHash'] as String;
      final managementPolicyVersion =
          value['managementPolicyVersion'] as String;
      final implementationVersion = value['implementationVersion'] as String;
      final lifecycle = StrategyLifecycle.values.firstWhere(
        (item) => item.name == value['lifecycle'],
      );
      final rawParameters = value['normalizedParameters'];
      if (strategyId.isEmpty ||
          strategyVersion.isEmpty ||
          parameterSchemaVersion < 1 ||
          snapshotHash.isEmpty ||
          managementPolicyVersion.isEmpty ||
          implementationVersion.isEmpty ||
          rawParameters is! Map<Object?, Object?>) {
        return null;
      }
      final parameters = <String, Object?>{};
      for (final entry in rawParameters.entries) {
        if (entry.key is! String) return null;
        parameters[entry.key! as String] = entry.value;
      }
      return StrategySnapshotIdentity(
        strategyId: strategyId,
        strategyVersion: strategyVersion,
        parameterSchemaVersion: parameterSchemaVersion,
        normalizedParameters: Map.unmodifiable(parameters),
        snapshotHash: snapshotHash,
        managementPolicyVersion: managementPolicyVersion,
        implementationVersion: implementationVersion,
        lifecycle: lifecycle,
      );
    } on Object {
      return null;
    }
  }
}

final class StrategyEvaluationRequest {
  const StrategyEvaluationRequest({
    required this.analysis,
    required this.capital,
    required this.riskPercent,
    required this.confluence,
    required this.languageCode,
    required this.cadence,
    this.professionalContext,
  });

  final TimeframeChartAnalysis analysis;
  final double capital;
  final double riskPercent;
  final Map<String, ChartDirection> confluence;
  final String languageCode;
  final SignalCadence cadence;
  final ProfessionalStrategyContext? professionalContext;
}

final class StrategyModule {
  StrategyModule({
    required this.selection,
    required this.strategyId,
    required this.humanName,
    required this.strategyVersion,
    required this.parameterSchemaVersion,
    required Map<String, Object?> parameterDefaults,
    required this.supportedTimeframes,
    required this.capabilities,
    required this.entrySemantics,
    required this.initialStopSemantics,
    required this.targetPlan,
    required this.invalidationRules,
    required this.managementPolicyVersion,
    required this.implementationVersion,
    this.supportedSymbolPattern = '*',
    this.lifecycle = StrategyLifecycle.active,
  }) : parameterDefaults = Map.unmodifiable(_normalizeMap(parameterDefaults));

  final AnalysisStrategy selection;
  final String strategyId;
  final String humanName;
  final String strategyVersion;
  final int parameterSchemaVersion;
  final Map<String, Object?> parameterDefaults;
  final Set<String> supportedTimeframes;
  final Set<String> capabilities;
  final String supportedSymbolPattern;
  final String entrySemantics;
  final String initialStopSemantics;
  final String targetPlan;
  final String invalidationRules;
  final String managementPolicyVersion;
  final String implementationVersion;
  final StrategyLifecycle lifecycle;

  bool get acceptsNewRuns => lifecycle == StrategyLifecycle.active;

  bool supports({required String symbol, required String timeframe}) =>
      symbol.trim().isNotEmpty && supportedTimeframes.contains(timeframe);

  StrategySnapshotIdentity? snapshot(Map<String, Object?> parameters) {
    final normalized = normalizeParameters(parameters);
    if (normalized == null) return null;
    final canonicalIdentity = <String, Object?>{
      'strategyId': strategyId,
      'strategyVersion': strategyVersion,
      'parameterSchemaVersion': parameterSchemaVersion,
      'normalizedParameters': normalized,
      'managementPolicyVersion': managementPolicyVersion,
      'implementationVersion': implementationVersion,
    };
    final hash = sha256
        .convert(utf8.encode(jsonEncode(canonicalIdentity)))
        .toString();
    return StrategySnapshotIdentity(
      strategyId: strategyId,
      strategyVersion: strategyVersion,
      parameterSchemaVersion: parameterSchemaVersion,
      normalizedParameters: normalized,
      snapshotHash: hash,
      managementPolicyVersion: managementPolicyVersion,
      implementationVersion: implementationVersion,
      lifecycle: lifecycle,
    );
  }

  Map<String, Object?>? normalizeParameters(Map<String, Object?> parameters) {
    if (parameters.keys.any((key) => !parameterDefaults.containsKey(key))) {
      return null;
    }
    final merged = <String, Object?>{...parameterDefaults, ...parameters};
    final cadence = merged['cadence'];
    if (cadence is! String ||
        !SignalCadence.values.any((item) => item.name == cadence)) {
      return null;
    }
    try {
      return Map.unmodifiable(_normalizeMap(merged));
    } on ArgumentError {
      return null;
    }
  }

  TradeIdea evaluate(StrategyEvaluationRequest request) =>
      ProfessionalStrategyEngine.create(
        analysis: request.analysis,
        capital: request.capital,
        riskPercent: request.riskPercent,
        confluence: request.confluence,
        languageCode: request.languageCode,
        strategy: selection,
        cadence: request.cadence,
        context: request.professionalContext,
      );
}

final class StrategyResolution {
  const StrategyResolution({required this.module, required this.snapshot});

  final StrategyModule module;
  final StrategySnapshotIdentity snapshot;
}

final class StrategyRegistry {
  StrategyRegistry(Iterable<StrategyModule> modules)
    : _modules = List.unmodifiable(modules) {
    final identities = <String>{};
    final activeSelections = <AnalysisStrategy>{};
    for (final module in _modules) {
      final identity = '${module.strategyId}@${module.strategyVersion}';
      if (!identities.add(identity)) {
        throw ArgumentError('Duplicate strategy identity: $identity');
      }
      if (module.acceptsNewRuns && !activeSelections.add(module.selection)) {
        throw ArgumentError(
          'Multiple active modules registered for ${module.selection.name}.',
        );
      }
    }
  }

  factory StrategyRegistry.standard() => StrategyRegistry(<StrategyModule>[
    _module(
      selection: AnalysisStrategy.structureZones,
      strategyId: 'structure_zones',
      humanName: 'Structure Zones',
      managementPolicyVersion: 'structure-zones-management/1.0',
    ),
    _module(
      selection: AnalysisStrategy.trendPullback,
      strategyId: 'trend_pullback',
      humanName: 'Trend Pullback',
      managementPolicyVersion: 'trend-pullback-management/1.0',
    ),
    _module(
      selection: AnalysisStrategy.momentumContinuation,
      strategyId: 'momentum_continuation',
      humanName: 'Momentum Continuation',
      managementPolicyVersion: 'momentum-management/1.0',
    ),
  ]);

  static final StrategyRegistry shared = StrategyRegistry.standard();

  final List<StrategyModule> _modules;

  List<StrategyModule> get modules => _modules;

  StrategyModule? historical({
    required String strategyId,
    required String strategyVersion,
  }) {
    for (final module in _modules) {
      if (module.strategyId == strategyId &&
          module.strategyVersion == strategyVersion) {
        return module;
      }
    }
    return null;
  }

  StrategyResolution? resolveForNewRun({
    required AnalysisStrategy selection,
    required String symbol,
    required String timeframe,
    required Map<String, Object?> parameters,
    String? requiredVersion,
  }) {
    for (final module in _modules) {
      if (module.selection != selection || !module.acceptsNewRuns) continue;
      if (requiredVersion != null &&
          module.strategyVersion != requiredVersion) {
        continue;
      }
      if (!module.supports(symbol: symbol, timeframe: timeframe)) return null;
      final snapshot = module.snapshot(parameters);
      if (snapshot == null) return null;
      return StrategyResolution(module: module, snapshot: snapshot);
    }
    return null;
  }

  static StrategyModule _module({
    required AnalysisStrategy selection,
    required String strategyId,
    required String humanName,
    required String managementPolicyVersion,
  }) => StrategyModule(
    selection: selection,
    strategyId: strategyId,
    humanName: humanName,
    strategyVersion: '1.0.0',
    parameterSchemaVersion: 1,
    parameterDefaults: const <String, Object?>{'cadence': 'balanced'},
    supportedTimeframes: const <String>{'5m', '15m', '1h', '4h', '1D'},
    capabilities: const <String>{
      'closed_candle_detection',
      'deterministic_entry',
      'initial_stop',
      'multi_target_plan',
      'invalidation',
    },
    entrySemantics: 'closed-candle deterministic entry zone',
    initialStopSemantics: 'structure/volatility derived initial stop',
    targetPlan: 'ordered deterministic take-profit targets',
    invalidationRules: 'strategy setup invalidation before execution overlays',
    managementPolicyVersion: managementPolicyVersion,
    implementationVersion: ProfessionalStrategyEngine.version,
  );
}

Map<String, Object?> _normalizeMap(Map<String, Object?> input) {
  final keys = input.keys.toList(growable: false)..sort();
  return <String, Object?>{
    for (final key in keys) key: _normalizeValue(input[key]),
  };
}

Object? _normalizeValue(Object? value) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError('Strategy parameters must be finite.');
    }
    return value;
  }
  if (value is num) {
    final number = value.toDouble();
    if (!number.isFinite) {
      throw ArgumentError('Strategy parameters must be finite.');
    }
    return number;
  }
  if (value is Map<Object?, Object?>) {
    final mapped = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError('Strategy parameter map keys must be strings.');
      }
      mapped[entry.key! as String] = entry.value;
    }
    return _normalizeMap(mapped);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_normalizeValue));
  }
  throw ArgumentError(
    'Unsupported strategy parameter value: ${value.runtimeType}',
  );
}
