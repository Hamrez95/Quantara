import 'global_pause_runtime_policy.dart';

enum GlobalPauseEventType {
  requested('global_pause_requested'),
  entered('global_pause_entered'),
  deferredForLiveManagement('global_pause_deferred_for_live_management'),
  fullOfflineEntered('global_pause_full_offline_entered'),
  resumeRequested('global_resume_requested'),
  resumeValidationFailed('global_resume_validation_failed'),
  resumeCompleted('global_resume_completed');

  const GlobalPauseEventType(this.stableName);

  final String stableName;
}

final class GlobalPauseActivitySnapshot {
  const GlobalPauseActivitySnapshot({
    required this.activeScanners,
    required this.activeSubscriptions,
    required this.activeTimers,
    required this.backgroundServiceActive,
  });

  final int activeScanners;
  final int activeSubscriptions;
  final int activeTimers;
  final bool backgroundServiceActive;

  Map<String, Object?> toJson() => <String, Object?>{
    'activeScanners': activeScanners,
    'activeSubscriptions': activeSubscriptions,
    'activeTimers': activeTimers,
    'backgroundServiceActive': backgroundServiceActive,
  };
}

final class GlobalPauseEvent {
  const GlobalPauseEvent({
    required this.type,
    required this.occurredAtUtc,
    required this.sessionId,
    required this.previousState,
    required this.newState,
    required this.openPositionCount,
    required this.openOrderCount,
    required this.protectionVerified,
    required this.activity,
    required this.reasonCode,
  });

  final GlobalPauseEventType type;
  final DateTime occurredAtUtc;
  final String sessionId;
  final GlobalPauseRuntimeMode previousState;
  final GlobalPauseRuntimeMode newState;
  final int openPositionCount;
  final int openOrderCount;
  final bool protectionVerified;
  final GlobalPauseActivitySnapshot activity;
  final String reasonCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'event': type.stableName,
    'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
    'sessionId': sessionId,
    'previousState': previousState.name,
    'newState': newState.name,
    'openPositionCount': openPositionCount,
    'openOrderCount': openOrderCount,
    'protectionVerified': protectionVerified,
    'activity': activity.toJson(),
    'reasonCode': reasonCode,
  };
}
