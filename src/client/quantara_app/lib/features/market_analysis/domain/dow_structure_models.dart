import 'dart:collection';

import 'market_chart_models.dart';

enum DowStructureScope { internal, external }

enum DowPivotKind { high, low }

enum DowPivotLabel { unknown, hh, hl, lh, ll, equalHigh, equalLow }

enum DowStructureState {
  unknown,
  bullishContinuation,
  bearishContinuation,
  range,
  transition,
  disorder,
}

enum DowStructureEventType {
  bosUp,
  bosDown,
  chochUp,
  chochDown,
  failedBreakUp,
  failedBreakDown,
  reclaimUp,
  reclaimDown,
}

enum DowRolloutMode { disabled, shadow, challengerGate }

final class DowStructureConfig {
  const DowStructureConfig({
    this.version = 'dow-structure/1.0',
    this.internalWing = 2,
    this.externalWing = 4,
    this.acceptanceAtrFraction = 0.10,
    this.minimumBodyAtrFraction = 0.30,
    this.equalPivotAtrFraction = 0.08,
    this.maximumGapMultiple = 1.6,
    this.maximumStalenessBars = 2,
    this.scoreCap = 20,
  });

  final String version;
  final int internalWing;
  final int externalWing;
  final double acceptanceAtrFraction;
  final double minimumBodyAtrFraction;
  final double equalPivotAtrFraction;
  final double maximumGapMultiple;
  final int maximumStalenessBars;
  final double scoreCap;

  void validate() {
    if (version.trim().isEmpty ||
        internalWing < 1 ||
        externalWing <= internalWing ||
        !acceptanceAtrFraction.isFinite ||
        acceptanceAtrFraction <= 0 ||
        !minimumBodyAtrFraction.isFinite ||
        minimumBodyAtrFraction <= 0 ||
        !equalPivotAtrFraction.isFinite ||
        equalPivotAtrFraction < 0 ||
        !maximumGapMultiple.isFinite ||
        maximumGapMultiple <= 1 ||
        maximumStalenessBars < 1 ||
        !scoreCap.isFinite ||
        scoreCap <= 0 ||
        scoreCap > 25) {
      throw ArgumentError('Dow structure configuration is invalid.');
    }
  }

  String get fingerprint => <Object>[
    version,
    internalWing,
    externalWing,
    acceptanceAtrFraction,
    minimumBodyAtrFraction,
    equalPivotAtrFraction,
    maximumGapMultiple,
    maximumStalenessBars,
    scoreCap,
  ].join('|');
}

final class DowStructureRollout {
  const DowStructureRollout({
    this.mode = DowRolloutMode.disabled,
    this.config = const DowStructureConfig(),
  });

  const DowStructureRollout.disabled()
    : mode = DowRolloutMode.disabled,
      config = const DowStructureConfig();

  const DowStructureRollout.shadow({this.config = const DowStructureConfig()})
    : mode = DowRolloutMode.shadow;

  const DowStructureRollout.challengerGate({
    this.config = const DowStructureConfig(),
  }) : mode = DowRolloutMode.challengerGate;

  final DowRolloutMode mode;
  final DowStructureConfig config;

  bool get enabled => mode != DowRolloutMode.disabled;
  bool get mayRejectNewCandidate => mode == DowRolloutMode.challengerGate;
}

final class DowPivot {
  const DowPivot({
    required this.scope,
    required this.kind,
    required this.label,
    required this.index,
    required this.price,
    required this.pivotTimeUtc,
    required this.confirmedAtUtc,
  });

  final DowStructureScope scope;
  final DowPivotKind kind;
  final DowPivotLabel label;
  final int index;
  final double price;
  final DateTime pivotTimeUtc;
  final DateTime confirmedAtUtc;

  String get reasonCode =>
      'dow:pivot:${scope.name}:${kind.name}:${label.name}:${confirmedAtUtc.toIso8601String()}';
}

final class DowStructureEvent {
  const DowStructureEvent({
    required this.type,
    required this.scope,
    required this.occurredAtUtc,
    required this.level,
    required this.close,
    required this.acceptanceDistance,
  });

  final DowStructureEventType type;
  final DowStructureScope scope;
  final DateTime occurredAtUtc;
  final double level;
  final double close;
  final double acceptanceDistance;

  String get reasonCode =>
      'dow:event:${scope.name}:${type.name}:${occurredAtUtc.toIso8601String()}';
}

final class DowScopeSnapshot {
  const DowScopeSnapshot({
    required this.scope,
    required this.state,
    required this.latestHigh,
    required this.latestLow,
    required this.protectedPivot,
    required this.latestEvent,
  });

  final DowStructureScope scope;
  final DowStructureState state;
  final DowPivot? latestHigh;
  final DowPivot? latestLow;
  final DowPivot? protectedPivot;
  final DowStructureEvent? latestEvent;

  ChartDirection get direction => switch (state) {
    DowStructureState.bullishContinuation => ChartDirection.bullish,
    DowStructureState.bearishContinuation => ChartDirection.bearish,
    _ => ChartDirection.sideways,
  };
}

final class DowStructureSnapshot {
  DowStructureSnapshot({
    required this.version,
    required this.configFingerprint,
    required this.analysisFingerprint,
    required this.generatedAtUtc,
    required this.valid,
    required this.stale,
    required this.gapped,
    required this.internal,
    required this.external,
    required Iterable<DowPivot> pivots,
    required Iterable<DowStructureEvent> events,
    required Iterable<String> reasonCodes,
  }) : pivots = UnmodifiableListView(pivots.toList(growable: false)),
       events = UnmodifiableListView(events.toList(growable: false)),
       reasonCodes = UnmodifiableListView(reasonCodes.toList(growable: false));

  final String version;
  final String configFingerprint;
  final String analysisFingerprint;
  final DateTime generatedAtUtc;
  final bool valid;
  final bool stale;
  final bool gapped;
  final DowScopeSnapshot internal;
  final DowScopeSnapshot external;
  final UnmodifiableListView<DowPivot> pivots;
  final UnmodifiableListView<DowStructureEvent> events;
  final UnmodifiableListView<String> reasonCodes;

  String get fingerprint => <Object>[
    version,
    configFingerprint,
    analysisFingerprint,
    generatedAtUtc.toIso8601String(),
    valid,
    stale,
    gapped,
    internal.state.name,
    external.state.name,
    for (final pivot in pivots)
      '${pivot.scope.name}:${pivot.kind.name}:${pivot.label.name}:${pivot.index}:${pivot.price}:${pivot.confirmedAtUtc.toIso8601String()}',
    for (final event in events)
      '${event.scope.name}:${event.type.name}:${event.level}:${event.close}:${event.occurredAtUtc.toIso8601String()}',
  ].join('|');
}

final class DowStructuralAlignment {
  DowStructuralAlignment({
    required this.version,
    required this.score,
    required this.cap,
    required this.allowed,
    required this.snapshot,
    required Iterable<String> reasonCodes,
  }) : cappedScore = score.clamp(0, cap).toDouble(),
       reasonCodes = UnmodifiableListView(reasonCodes.toList(growable: false));

  final String version;
  final double score;
  final double cap;
  final double cappedScore;
  final bool allowed;
  final DowStructureSnapshot snapshot;
  final UnmodifiableListView<String> reasonCodes;
}
