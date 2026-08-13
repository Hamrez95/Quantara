/// Immutable observation captured from Quantara for offline/read-only review.
///
/// This contract intentionally contains data only. It has no command surface and
/// must be sanitized before it crosses the supervisor boundary.
final class SupervisorSnapshot {
  SupervisorSnapshot({
    required DateTime capturedAtUtc,
    required Map<String, Object?> runtime,
    required Map<String, Object?> risk,
    required Map<String, Object?> strategy,
    List<Map<String, Object?>> openPositions = const [],
    List<Map<String, Object?>> pendingOrders = const [],
    List<Map<String, Object?>> recentEvents = const [],
  }) : capturedAtUtc = capturedAtUtc.toUtc(),
       runtime = Map.unmodifiable(runtime),
       risk = Map.unmodifiable(risk),
       strategy = Map.unmodifiable(strategy),
       openPositions = List.unmodifiable(openPositions.map(Map.unmodifiable)),
       pendingOrders = List.unmodifiable(pendingOrders.map(Map.unmodifiable)),
       recentEvents = List.unmodifiable(recentEvents.map(Map.unmodifiable));

  static const String schemaVersion = '1';

  final DateTime capturedAtUtc;
  final Map<String, Object?> runtime;
  final Map<String, Object?> risk;
  final Map<String, Object?> strategy;
  final List<Map<String, Object?>> openPositions;
  final List<Map<String, Object?>> pendingOrders;
  final List<Map<String, Object?>> recentEvents;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'capturedAtUtc': capturedAtUtc.toIso8601String(),
    'runtime': runtime,
    'risk': risk,
    'strategy': strategy,
    'openPositions': openPositions,
    'pendingOrders': pendingOrders,
    'recentEvents': recentEvents,
  };
}
