import 'dart:collection';

import 'strategy_promotion_models.dart';

enum StrategyPromotionStage {
  researchOnly,
  shadowEligible,
  paperEligible,
  cappedCanaryEligible,
  autonomousEligible,
}

enum StrategyPromotionEventKind { proposal, promotion, drift, rollback }

enum StrategyPromotionActor { deterministicPolicy, aiAdvisor }

enum StrategyDriftAction {
  observe,
  reduceAllocation,
  shadowOnly,
  blockNewEntries,
  requireResearch,
}

final class StrategyRuntimeIdentity {
  const StrategyRuntimeIdentity({
    required this.slotId,
    required this.strategyId,
    required this.strategyVersion,
    required this.featureSetVersion,
    required this.regimeClassifierVersion,
    required this.rankingPolicyVersion,
    required this.riskPolicyVersion,
    required this.allocatorPolicyVersion,
    required this.configHash,
    required this.sourceBuild,
  });

  factory StrategyRuntimeIdentity.fromJson(
    Map<String, Object?> json,
  ) => StrategyRuntimeIdentity(
    slotId: json['slotId']?.toString() ?? '',
    strategyId: json['strategyId']?.toString() ?? '',
    strategyVersion: json['strategyVersion']?.toString() ?? '',
    featureSetVersion: json['featureSetVersion']?.toString() ?? '',
    regimeClassifierVersion: json['regimeClassifierVersion']?.toString() ?? '',
    rankingPolicyVersion: json['rankingPolicyVersion']?.toString() ?? '',
    riskPolicyVersion: json['riskPolicyVersion']?.toString() ?? '',
    allocatorPolicyVersion: json['allocatorPolicyVersion']?.toString() ?? '',
    configHash: json['configHash']?.toString() ?? '',
    sourceBuild: json['sourceBuild']?.toString() ?? '',
  );

  final String slotId;
  final String strategyId;
  final String strategyVersion;
  final String featureSetVersion;
  final String regimeClassifierVersion;
  final String rankingPolicyVersion;
  final String riskPolicyVersion;
  final String allocatorPolicyVersion;
  final String configHash;
  final String sourceBuild;

  bool get valid => [
    slotId,
    strategyId,
    strategyVersion,
    featureSetVersion,
    regimeClassifierVersion,
    rankingPolicyVersion,
    riskPolicyVersion,
    allocatorPolicyVersion,
    configHash,
    sourceBuild,
  ].every((value) => value.trim().isNotEmpty);

  String get key =>
      '$slotId|$strategyId@$strategyVersion|$featureSetVersion|'
      '$regimeClassifierVersion|$rankingPolicyVersion|$riskPolicyVersion|'
      '$allocatorPolicyVersion|$configHash|$sourceBuild';

  Map<String, Object?> toJson() => {
    'slotId': slotId,
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'featureSetVersion': featureSetVersion,
    'regimeClassifierVersion': regimeClassifierVersion,
    'rankingPolicyVersion': rankingPolicyVersion,
    'riskPolicyVersion': riskPolicyVersion,
    'allocatorPolicyVersion': allocatorPolicyVersion,
    'configHash': configHash,
    'sourceBuild': sourceBuild,
  };
}

final class StrategyPromotionRegistryEvent {
  StrategyPromotionRegistryEvent({
    required this.sequence,
    required this.eventId,
    required this.kind,
    required this.actor,
    required this.identity,
    required this.stage,
    required this.driftAction,
    required Iterable<String> evidenceIds,
    required this.reasonCode,
    required this.recordedAtUtc,
    this.previousChampion,
    this.previousStage,
  }) : evidenceIds = UnmodifiableListView(
         evidenceIds.map((value) => value.trim()).toList(growable: false),
       ) {
    if (sequence <= 0 ||
        eventId.trim().isEmpty ||
        !identity.valid ||
        reasonCode.trim().isEmpty ||
        !recordedAtUtc.isUtc ||
        this.evidenceIds.isEmpty ||
        this.evidenceIds.any((value) => value.isEmpty) ||
        this.evidenceIds.toSet().length != this.evidenceIds.length) {
      throw const FormatException('Promotion registry event is incomplete.');
    }
    if (actor == StrategyPromotionActor.aiAdvisor &&
        kind != StrategyPromotionEventKind.proposal) {
      throw StateError(
        'AI may propose challengers but cannot mutate promotion state.',
      );
    }
    if ((previousChampion == null) != (previousStage == null)) {
      throw const FormatException(
        'Previous champion identity and stage must be recorded together.',
      );
    }
  }

  factory StrategyPromotionRegistryEvent.fromJson(Map<String, Object?> json) {
    final identityJson = json['identity'];
    final previousJson = json['previousChampion'];
    final evidence = json['evidenceIds'];
    final kind = StrategyPromotionEventKind.values
        .where((value) => value.name == json['kind'])
        .firstOrNull;
    final actor = StrategyPromotionActor.values
        .where((value) => value.name == json['actor'])
        .firstOrNull;
    final stage = StrategyPromotionStage.values
        .where((value) => value.name == json['stage'])
        .firstOrNull;
    final driftAction = StrategyDriftAction.values
        .where((value) => value.name == json['driftAction'])
        .firstOrNull;
    final previousStageName = json['previousStage']?.toString();
    final previousStage = previousStageName == null
        ? null
        : StrategyPromotionStage.values
              .where((value) => value.name == previousStageName)
              .firstOrNull;
    if (identityJson is! Map ||
        evidence is! List ||
        kind == null ||
        actor == null ||
        stage == null ||
        driftAction == null ||
        (previousStageName != null && previousStage == null)) {
      throw const FormatException('Promotion registry JSON is invalid.');
    }
    return StrategyPromotionRegistryEvent(
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      eventId: json['eventId']?.toString() ?? '',
      kind: kind,
      actor: actor,
      identity: StrategyRuntimeIdentity.fromJson(
        Map<String, Object?>.from(identityJson),
      ),
      stage: stage,
      driftAction: driftAction,
      evidenceIds: evidence.map((value) => value.toString()),
      reasonCode: json['reasonCode']?.toString() ?? '',
      recordedAtUtc: DateTime.parse(json['recordedAtUtc']!.toString()).toUtc(),
      previousChampion: previousJson is Map
          ? StrategyRuntimeIdentity.fromJson(
              Map<String, Object?>.from(previousJson),
            )
          : null,
      previousStage: previousStage,
    );
  }

  static const schemaVersion = 1;

  final int sequence;
  final String eventId;
  final StrategyPromotionEventKind kind;
  final StrategyPromotionActor actor;
  final StrategyRuntimeIdentity identity;
  final StrategyPromotionStage stage;
  final StrategyDriftAction driftAction;
  final UnmodifiableListView<String> evidenceIds;
  final String reasonCode;
  final DateTime recordedAtUtc;
  final StrategyRuntimeIdentity? previousChampion;
  final StrategyPromotionStage? previousStage;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'sequence': sequence,
    'eventId': eventId,
    'kind': kind.name,
    'actor': actor.name,
    'identity': identity.toJson(),
    'stage': stage.name,
    'driftAction': driftAction.name,
    'evidenceIds': evidenceIds.toList(growable: false),
    'reasonCode': reasonCode,
    'recordedAtUtc': recordedAtUtc.toIso8601String(),
    'previousChampion': previousChampion?.toJson(),
    'previousStage': previousStage?.name,
  };
}

final class StrategyPromotionSlotSnapshot {
  const StrategyPromotionSlotSnapshot({
    required this.slotId,
    required this.champion,
    required this.championStage,
    required this.challenger,
    required this.rollbackChampion,
    required this.rollbackStage,
    required this.driftAction,
    required this.reasonCode,
    required this.evidenceIds,
    required this.updatedAtUtc,
  });

  final String slotId;
  final StrategyRuntimeIdentity? champion;
  final StrategyPromotionStage? championStage;
  final StrategyRuntimeIdentity? challenger;
  final StrategyRuntimeIdentity? rollbackChampion;
  final StrategyPromotionStage? rollbackStage;
  final StrategyDriftAction driftAction;
  final String reasonCode;
  final List<String> evidenceIds;
  final DateTime? updatedAtUtc;

  bool get liveEntriesAllowed =>
      champion != null &&
      (championStage == StrategyPromotionStage.cappedCanaryEligible ||
          championStage == StrategyPromotionStage.autonomousEligible) &&
      driftAction != StrategyDriftAction.shadowOnly &&
      driftAction != StrategyDriftAction.blockNewEntries &&
      driftAction != StrategyDriftAction.requireResearch;

  Map<String, Object?> toExplanationJson() => {
    'slotId': slotId,
    'champion': champion?.toJson(),
    'championStage': championStage?.name,
    'challenger': challenger?.toJson(),
    'rollbackChampion': rollbackChampion?.toJson(),
    'rollbackStage': rollbackStage?.name,
    'driftAction': driftAction.name,
    'reasonCode': reasonCode,
    'evidenceIds': evidenceIds,
    'liveEntriesAllowed': liveEntriesAllowed,
    'updatedAtUtc': updatedAtUtc?.toIso8601String(),
  };
}

final class StrategyPromotionRegistry {
  StrategyPromotionRegistry._();

  factory StrategyPromotionRegistry.empty() => StrategyPromotionRegistry._();

  factory StrategyPromotionRegistry.restore(
    Iterable<StrategyPromotionRegistryEvent> events,
  ) {
    final registry = StrategyPromotionRegistry._();
    for (final event in events) {
      registry._appendRestored(event);
    }
    return registry;
  }

  final List<StrategyPromotionRegistryEvent> _events = [];
  final Map<String, StrategyPromotionSlotSnapshot> _slots = {};

  UnmodifiableListView<StrategyPromotionRegistryEvent> get events =>
      UnmodifiableListView(_events);

  StrategyPromotionSlotSnapshot snapshot(String slotId) =>
      _slots[slotId] ??
      StrategyPromotionSlotSnapshot(
        slotId: slotId,
        champion: null,
        championStage: null,
        challenger: null,
        rollbackChampion: null,
        rollbackStage: null,
        driftAction: StrategyDriftAction.observe,
        reasonCode: 'strategy.promotion.uninitialized',
        evidenceIds: const [],
        updatedAtUtc: null,
      );

  StrategyPromotionRegistryEvent proposeChallenger({
    required String eventId,
    required StrategyRuntimeIdentity challenger,
    required Iterable<String> evidenceIds,
    required DateTime recordedAtUtc,
    StrategyPromotionActor actor = StrategyPromotionActor.aiAdvisor,
  }) {
    final current = snapshot(challenger.slotId);
    final event = StrategyPromotionRegistryEvent(
      sequence: _events.length + 1,
      eventId: eventId,
      kind: StrategyPromotionEventKind.proposal,
      actor: actor,
      identity: challenger,
      stage: StrategyPromotionStage.researchOnly,
      driftAction: current.driftAction,
      evidenceIds: evidenceIds,
      reasonCode: 'strategy.promotion.challenger_proposed',
      recordedAtUtc: recordedAtUtc,
    );
    _append(event);
    return event;
  }

  StrategyPromotionRegistryEvent promote({
    required String eventId,
    required StrategyRuntimeIdentity candidate,
    required StrategyPromotionPacket evidence,
    required StrategyPromotionStage targetStage,
    required Iterable<String> evidenceIds,
    required DateTime recordedAtUtc,
    StrategyPromotionActor actor = StrategyPromotionActor.deterministicPolicy,
  }) {
    if (actor != StrategyPromotionActor.deterministicPolicy) {
      throw StateError('Only deterministic policy can promote a strategy.');
    }
    if (!_packetMatches(candidate, evidence)) {
      throw StateError(
        'Promotion packet identity does not match the candidate.',
      );
    }
    if (!_evidenceAllows(evidence, targetStage)) {
      throw StateError(
        'Promotion evidence is not sufficient for the target stage.',
      );
    }
    final current = snapshot(candidate.slotId);
    final allowedNext = switch (current.championStage) {
      null => StrategyPromotionStage.shadowEligible,
      StrategyPromotionStage.researchOnly =>
        StrategyPromotionStage.shadowEligible,
      StrategyPromotionStage.shadowEligible =>
        StrategyPromotionStage.paperEligible,
      StrategyPromotionStage.paperEligible =>
        StrategyPromotionStage.cappedCanaryEligible,
      StrategyPromotionStage.cappedCanaryEligible =>
        StrategyPromotionStage.autonomousEligible,
      StrategyPromotionStage.autonomousEligible =>
        StrategyPromotionStage.autonomousEligible,
    };
    if (targetStage != allowedNext &&
        !(current.champion == null &&
            targetStage == StrategyPromotionStage.shadowEligible)) {
      throw StateError('Promotion stages cannot be skipped.');
    }
    if (current.challenger != null &&
        current.challenger!.key != candidate.key) {
      throw StateError(
        'Only the registered challenger can replace the champion.',
      );
    }
    final event = StrategyPromotionRegistryEvent(
      sequence: _events.length + 1,
      eventId: eventId,
      kind: StrategyPromotionEventKind.promotion,
      actor: actor,
      identity: candidate,
      stage: targetStage,
      driftAction: StrategyDriftAction.observe,
      evidenceIds: evidenceIds,
      reasonCode: 'strategy.promotion.${targetStage.name}',
      recordedAtUtc: recordedAtUtc,
      previousChampion: current.champion,
      previousStage: current.championStage,
    );
    _append(event);
    return event;
  }

  StrategyPromotionRegistryEvent recordDrift({
    required String eventId,
    required String slotId,
    required Iterable<ValidationDowngradeReason> reasons,
    required Iterable<String> evidenceIds,
    required DateTime recordedAtUtc,
  }) {
    final current = snapshot(slotId);
    final champion = current.champion;
    if (champion == null || current.championStage == null) {
      throw StateError('Drift cannot be recorded without an active champion.');
    }
    final normalizedReasons = reasons.toSet();
    final action = _driftAction(normalizedReasons);
    final reasonCode = normalizedReasons.isEmpty
        ? 'strategy.drift.clear'
        : 'strategy.drift.${normalizedReasons.map((value) => value.name).join('+')}';
    final event = StrategyPromotionRegistryEvent(
      sequence: _events.length + 1,
      eventId: eventId,
      kind: StrategyPromotionEventKind.drift,
      actor: StrategyPromotionActor.deterministicPolicy,
      identity: champion,
      stage: current.championStage!,
      driftAction: action,
      evidenceIds: evidenceIds,
      reasonCode: reasonCode,
      recordedAtUtc: recordedAtUtc,
    );
    _append(event);
    return event;
  }

  StrategyPromotionRegistryEvent rollback({
    required String eventId,
    required String slotId,
    required Iterable<String> evidenceIds,
    required DateTime recordedAtUtc,
  }) {
    final current = snapshot(slotId);
    final rollbackChampion = current.rollbackChampion;
    final rollbackStage = current.rollbackStage;
    if (rollbackChampion == null || rollbackStage == null) {
      throw StateError(
        'No previously certified champion is available for rollback.',
      );
    }
    final event = StrategyPromotionRegistryEvent(
      sequence: _events.length + 1,
      eventId: eventId,
      kind: StrategyPromotionEventKind.rollback,
      actor: StrategyPromotionActor.deterministicPolicy,
      identity: rollbackChampion,
      stage: rollbackStage,
      driftAction: StrategyDriftAction.observe,
      evidenceIds: evidenceIds,
      reasonCode: 'strategy.promotion.rollback',
      recordedAtUtc: recordedAtUtc,
      previousChampion: current.champion,
      previousStage: current.championStage,
    );
    _append(event);
    return event;
  }

  static bool _packetMatches(
    StrategyRuntimeIdentity identity,
    StrategyPromotionPacket packet,
  ) =>
      packet.identity.playbook == identity.strategyId &&
      packet.identity.playbookVersion == identity.strategyVersion &&
      packet.provenance.configHash == identity.configHash &&
      packet.provenance.sourceBuild == identity.sourceBuild;

  static bool _evidenceAllows(
    StrategyPromotionPacket packet,
    StrategyPromotionStage targetStage,
  ) => switch (targetStage) {
    StrategyPromotionStage.researchOnly => false,
    StrategyPromotionStage.shadowEligible =>
      packet.reproducible &&
          packet.parameterStability.sharpOptimum == false &&
          packet.bootstrap.p05R > 0 &&
          packet.netExpectancyR > 0,
    StrategyPromotionStage.paperEligible ||
    StrategyPromotionStage.cappedCanaryEligible ||
    StrategyPromotionStage.autonomousEligible =>
      packet.promotionEvidenceComplete,
  };

  static StrategyDriftAction _driftAction(
    Set<ValidationDowngradeReason> reasons,
  ) {
    if (reasons.isEmpty) return StrategyDriftAction.observe;
    if (reasons.contains(ValidationDowngradeReason.holdoutNotPositive) ||
        reasons.contains(
          ValidationDowngradeReason.survivorshipBiasUncontrolled,
        )) {
      return StrategyDriftAction.requireResearch;
    }
    if (reasons.contains(ValidationDowngradeReason.calibrationDrift) ||
        reasons.contains(ValidationDowngradeReason.coverageCollapse)) {
      return StrategyDriftAction.shadowOnly;
    }
    if (reasons.length >= 2) return StrategyDriftAction.blockNewEntries;
    return StrategyDriftAction.reduceAllocation;
  }

  void _append(StrategyPromotionRegistryEvent event) {
    if (_events.any((existing) => existing.eventId == event.eventId)) {
      throw StateError(
        'Promotion registry event IDs are append-only and unique.',
      );
    }
    if (event.sequence != _events.length + 1) {
      throw StateError('Promotion registry sequence must be contiguous.');
    }
    final current = snapshot(event.identity.slotId);
    if (current.updatedAtUtc != null &&
        event.recordedAtUtc.isBefore(current.updatedAtUtc!)) {
      throw StateError('Promotion registry time cannot move backwards.');
    }
    _events.add(event);
    _apply(event, current);
  }

  void _appendRestored(StrategyPromotionRegistryEvent event) => _append(event);

  void _apply(
    StrategyPromotionRegistryEvent event,
    StrategyPromotionSlotSnapshot current,
  ) {
    switch (event.kind) {
      case StrategyPromotionEventKind.proposal:
        _slots[event.identity.slotId] = StrategyPromotionSlotSnapshot(
          slotId: event.identity.slotId,
          champion: current.champion,
          championStage: current.championStage,
          challenger: event.identity,
          rollbackChampion: current.rollbackChampion,
          rollbackStage: current.rollbackStage,
          driftAction: current.driftAction,
          reasonCode: event.reasonCode,
          evidenceIds: event.evidenceIds,
          updatedAtUtc: event.recordedAtUtc,
        );
      case StrategyPromotionEventKind.promotion:
      case StrategyPromotionEventKind.rollback:
        if (event.previousChampion?.key != current.champion?.key ||
            event.previousStage != current.championStage) {
          throw StateError(
            'Promotion history does not match the current champion.',
          );
        }
        _slots[event.identity.slotId] = StrategyPromotionSlotSnapshot(
          slotId: event.identity.slotId,
          champion: event.identity,
          championStage: event.stage,
          challenger: null,
          rollbackChampion: event.previousChampion,
          rollbackStage: event.previousStage,
          driftAction: event.driftAction,
          reasonCode: event.reasonCode,
          evidenceIds: event.evidenceIds,
          updatedAtUtc: event.recordedAtUtc,
        );
      case StrategyPromotionEventKind.drift:
        if (current.champion?.key != event.identity.key) {
          throw StateError('Drift evidence must target the active champion.');
        }
        _slots[event.identity.slotId] = StrategyPromotionSlotSnapshot(
          slotId: event.identity.slotId,
          champion: current.champion,
          championStage: current.championStage,
          challenger: current.challenger,
          rollbackChampion: current.rollbackChampion,
          rollbackStage: current.rollbackStage,
          driftAction: event.driftAction,
          reasonCode: event.reasonCode,
          evidenceIds: event.evidenceIds,
          updatedAtUtc: event.recordedAtUtc,
        );
    }
  }
}
