import 'dart:collection';

enum SupportDecisionStage {
  market,
  strategy,
  ranking,
  risk,
  allocator,
  policy,
  execution,
  reconciliation,
  journal,
}

final class SupportVisibleValue {
  const SupportVisibleValue({
    required this.key,
    required this.value,
    required this.sourceType,
    required this.sourceEvidenceId,
  });

  final String key;
  final String value;
  final String sourceType;
  final String sourceEvidenceId;

  Map<String, Object?> toJson() => {
    'key': key,
    'value': value,
    'sourceType': sourceType,
    'sourceEvidenceId': sourceEvidenceId,
  };
}

final class SupportDecisionTraceStage {
  const SupportDecisionTraceStage({
    required this.stage,
    required this.status,
    required this.reasonCode,
    this.evidenceIds = const [],
  });

  final SupportDecisionStage stage;
  final String status;
  final String reasonCode;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'stage': stage.name,
    'status': status,
    'reasonCode': reasonCode,
    'evidenceIds': evidenceIds,
  };
}

final class SupportCapacityExplanation {
  const SupportCapacityExplanation({
    required this.scannerHeartbeatAtUtc,
    required this.managedPositionCount,
    required this.totalSlots,
    required this.availableSlots,
    required this.riskCapacity,
    required this.marginCapacity,
    required this.correlationCapacity,
    required this.reservedCapacity,
    required this.disposition,
    required this.reasonCode,
    this.evidenceIds = const [],
  });

  final DateTime scannerHeartbeatAtUtc;
  final int managedPositionCount;
  final int totalSlots;
  final int availableSlots;
  final String riskCapacity;
  final String marginCapacity;
  final String correlationCapacity;
  final String reservedCapacity;
  final String disposition;
  final String reasonCode;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'scannerHeartbeatAtUtc': scannerHeartbeatAtUtc.toUtc().toIso8601String(),
    'managedPositionCount': managedPositionCount,
    'totalSlots': totalSlots,
    'availableSlots': availableSlots,
    'riskCapacity': riskCapacity,
    'marginCapacity': marginCapacity,
    'correlationCapacity': correlationCapacity,
    'reservedCapacity': reservedCapacity,
    'disposition': disposition,
    'reasonCode': reasonCode,
    'evidenceIds': evidenceIds,
  };
}

/// A bounded, read-only snapshot of what the user sees and why the runtime did
/// or did not advance a candidate. It contains no mutation callbacks or exchange
/// credentials and is intended only for an explicitly enabled Support Session.
final class SupportSessionDiagnosticSnapshot {
  SupportSessionDiagnosticSnapshot({
    required this.correlationId,
    required this.observedAtUtc,
    required this.route,
    required this.selectedTab,
    required this.symbol,
    required this.timeframe,
    required this.strategyId,
    required this.mode,
    required this.autoTradeState,
    required this.localLiveState,
    required this.uiState,
    required this.appBuild,
    required this.configVersion,
    required Iterable<SupportVisibleValue> visibleValues,
    required Iterable<SupportDecisionTraceStage> decisionTrace,
    required this.capacity,
  }) : visibleValues = UnmodifiableListView(
         visibleValues.toList(growable: false),
       ),
       decisionTrace = UnmodifiableListView(
         decisionTrace.toList(growable: false),
       ) {
    if (correlationId.trim().isEmpty ||
        route.trim().isEmpty ||
        mode.trim().isEmpty ||
        appBuild.trim().isEmpty ||
        configVersion.trim().isEmpty) {
      throw const FormatException('Support diagnostic identity is incomplete.');
    }
    if (this.visibleValues.length > maximumVisibleValues) {
      throw StateError('Support diagnostic visible-value bound exceeded.');
    }
    if (this.decisionTrace.length > SupportDecisionStage.values.length) {
      throw StateError('Support diagnostic decision-stage bound exceeded.');
    }
    final stages = this.decisionTrace.map((item) => item.stage).toList();
    if (stages.toSet().length != stages.length) {
      throw const FormatException(
        'Support diagnostic decision stages must be unique.',
      );
    }
    if (capacity.managedPositionCount < 0 ||
        capacity.totalSlots < 0 ||
        capacity.availableSlots < 0 ||
        capacity.availableSlots > capacity.totalSlots) {
      throw const FormatException('Support diagnostic capacity is invalid.');
    }
  }

  static const maximumVisibleValues = 32;

  final String correlationId;
  final DateTime observedAtUtc;
  final String route;
  final String selectedTab;
  final String symbol;
  final String timeframe;
  final String strategyId;
  final String mode;
  final String autoTradeState;
  final String localLiveState;
  final String uiState;
  final String appBuild;
  final String configVersion;
  final UnmodifiableListView<SupportVisibleValue> visibleValues;
  final UnmodifiableListView<SupportDecisionTraceStage> decisionTrace;
  final SupportCapacityExplanation capacity;

  Map<String, Object?> toDiagnosticSections() {
    final stageByType = {for (final item in decisionTrace) item.stage: item};
    final completeTrace = SupportDecisionStage.values
        .map((stage) {
          final item = stageByType[stage];
          return item?.toJson() ??
              <String, Object?>{
                'stage': stage.name,
                'status': 'missing',
                'reasonCode': 'support.trace.stage_missing',
                'evidenceIds': const <String>[],
              };
        })
        .toList(growable: false);

    return <String, Object?>{
      'supportVisibleAppState': <String, Object?>{
        'route': route,
        'selectedTab': selectedTab,
        'symbol': symbol,
        'timeframe': timeframe,
        'strategyId': strategyId,
        'mode': mode,
        'autoTradeState': autoTradeState,
        'localLiveState': localLiveState,
        'uiState': uiState,
        'appBuild': appBuild,
        'configVersion': configVersion,
        'correlationId': correlationId,
        'visibleValues': visibleValues
            .map((item) => item.toJson())
            .toList(growable: false),
      },
      'supportDecisionTrace': <String, Object?>{
        'correlationId': correlationId,
        'stages': completeTrace,
      },
      'supportCapacityExplanation': <String, Object?>{
        'correlationId': correlationId,
        ...capacity.toJson(),
      },
    };
  }
}
