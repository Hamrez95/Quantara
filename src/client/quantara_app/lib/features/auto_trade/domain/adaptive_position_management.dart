import 'package:flutter/foundation.dart';

import '../../owner_alpha/domain/owner_alpha_models.dart';

enum AdaptiveManagementState {
  watch,
  armed,
  entered,
  active,
  protected,
  runner,
  exited,
  invalidated,
}

enum AdaptiveManagementEventKind {
  arm,
  entryConfirmed,
  managementActivated,
  protectionConfirmed,
  runnerActivated,
  exitConfirmed,
  invalidate,
}

@immutable
final class AdaptiveManagementEvent {
  const AdaptiveManagementEvent({required this.id, required this.kind});

  final String id;
  final AdaptiveManagementEventKind kind;
}

@immutable
final class AdaptiveManagementSnapshot {
  AdaptiveManagementSnapshot({
    required this.state,
    required this.revision,
    required Set<String> processedEventIds,
  }) : processedEventIds = Set.unmodifiable(processedEventIds);

  factory AdaptiveManagementSnapshot.initial() => AdaptiveManagementSnapshot(
    state: AdaptiveManagementState.watch,
    revision: 0,
    processedEventIds: const {},
  );

  final AdaptiveManagementState state;
  final int revision;
  final Set<String> processedEventIds;

  bool get terminal =>
      state == AdaptiveManagementState.exited ||
      state == AdaptiveManagementState.invalidated;

  AdaptiveManagementSnapshot apply(AdaptiveManagementEvent event) {
    final eventId = event.id.trim();
    if (eventId.isEmpty) {
      throw const FormatException('Management event id is required.');
    }
    if (processedEventIds.contains(eventId)) return this;
    if (terminal) {
      return AdaptiveManagementSnapshot(
        state: state,
        revision: revision,
        processedEventIds: {...processedEventIds, eventId},
      );
    }
    final next = _transition(state, event.kind);
    return AdaptiveManagementSnapshot(
      state: next,
      revision: revision + 1,
      processedEventIds: {...processedEventIds, eventId},
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'state': state.name,
    'revision': revision,
    'processedEventIds': processedEventIds.toList(growable: false)..sort(),
  };

  factory AdaptiveManagementSnapshot.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Management snapshot is invalid.');
    }
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    final version = (json['version'] as num?)?.toInt();
    final revision = (json['revision'] as num?)?.toInt();
    final stateName = json['state']?.toString() ?? '';
    if (version != 1 || revision == null || revision < 0) {
      throw const FormatException('Management snapshot version is invalid.');
    }
    final state = AdaptiveManagementState.values.where(
      (item) => item.name == stateName,
    );
    if (state.length != 1) {
      throw const FormatException('Management snapshot state is invalid.');
    }
    final ids = (json['processedEventIds'] as List<Object?>? ?? const [])
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return AdaptiveManagementSnapshot(
      state: state.single,
      revision: revision,
      processedEventIds: ids,
    );
  }

  static AdaptiveManagementState _transition(
    AdaptiveManagementState current,
    AdaptiveManagementEventKind event,
  ) {
    if (event == AdaptiveManagementEventKind.invalidate) {
      return AdaptiveManagementState.invalidated;
    }
    if (event == AdaptiveManagementEventKind.exitConfirmed &&
        current.index >= AdaptiveManagementState.entered.index) {
      return AdaptiveManagementState.exited;
    }
    return switch ((current, event)) {
      (AdaptiveManagementState.watch, AdaptiveManagementEventKind.arm) =>
        AdaptiveManagementState.armed,
      (
        AdaptiveManagementState.armed,
        AdaptiveManagementEventKind.entryConfirmed,
      ) =>
        AdaptiveManagementState.entered,
      (
        AdaptiveManagementState.entered,
        AdaptiveManagementEventKind.managementActivated,
      ) =>
        AdaptiveManagementState.active,
      (
        AdaptiveManagementState.active,
        AdaptiveManagementEventKind.protectionConfirmed,
      ) =>
        AdaptiveManagementState.protected,
      (
        AdaptiveManagementState.protected,
        AdaptiveManagementEventKind.runnerActivated,
      ) =>
        AdaptiveManagementState.runner,
      _ => throw StateError(
        'Invalid adaptive management transition: ${current.name} + ${event.name}.',
      ),
    };
  }
}

enum ManagementInvariantReason {
  allowed,
  invalidInput,
  nonActionableDirection,
  stopWouldWiden,
  exposureWouldIncrease,
}

@immutable
final class ManagementInvariantDecision {
  const ManagementInvariantDecision({
    required this.allowed,
    required this.reason,
  });

  final bool allowed;
  final ManagementInvariantReason reason;
}

abstract final class AdaptiveManagementInvariants {
  static ManagementInvariantDecision evaluateProtectionMutation({
    required TradeDirection direction,
    required double currentConfirmedStop,
    required double proposedStop,
    required double currentQuantity,
    required double proposedQuantity,
    double tolerance = 1e-9,
  }) {
    if (direction == TradeDirection.wait) {
      return const ManagementInvariantDecision(
        allowed: false,
        reason: ManagementInvariantReason.nonActionableDirection,
      );
    }
    final values = [
      currentConfirmedStop,
      proposedStop,
      currentQuantity,
      proposedQuantity,
      tolerance,
    ];
    if (values.any((value) => !value.isFinite) ||
        currentConfirmedStop <= 0 ||
        proposedStop <= 0 ||
        currentQuantity < 0 ||
        proposedQuantity < 0 ||
        tolerance < 0) {
      return const ManagementInvariantDecision(
        allowed: false,
        reason: ManagementInvariantReason.invalidInput,
      );
    }
    if (proposedQuantity > currentQuantity + tolerance) {
      return const ManagementInvariantDecision(
        allowed: false,
        reason: ManagementInvariantReason.exposureWouldIncrease,
      );
    }
    final widensStop = direction == TradeDirection.long
        ? proposedStop + tolerance < currentConfirmedStop
        : proposedStop - tolerance > currentConfirmedStop;
    if (widensStop) {
      return const ManagementInvariantDecision(
        allowed: false,
        reason: ManagementInvariantReason.stopWouldWiden,
      );
    }
    return const ManagementInvariantDecision(
      allowed: true,
      reason: ManagementInvariantReason.allowed,
    );
  }
}
