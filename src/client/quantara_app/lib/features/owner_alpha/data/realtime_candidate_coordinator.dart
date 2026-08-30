import '../domain/candidate_audit_models.dart';
import '../domain/realtime_candidate_models.dart';
import '../domain/realtime_market_event_models.dart';
import 'candidate_audit_retention_policy.dart';
import 'realtime_candidate_registry.dart';

export 'candidate_audit_retention_policy.dart'
    show CandidateAuditPersistenceDecision;

enum CandidateCoordinationOutcome {
  committed,
  rejected,
  durabilityFailed,
  commitConflict,
}

abstract interface class CandidateAuditMetricSink {
  Future<void> increment(StreamEventDisposition disposition);
}

final class NoopCandidateAuditMetricSink implements CandidateAuditMetricSink {
  const NoopCandidateAuditMetricSink();

  @override
  Future<void> increment(StreamEventDisposition disposition) async {}
}

final class CandidateCoordinationResult {
  const CandidateCoordinationResult({
    required this.outcome,
    required this.update,
    required this.persistenceDecision,
    required this.failureMessage,
    required this.diagnosticFailureMessage,
  });

  final CandidateCoordinationOutcome outcome;
  final CandidateRegistryUpdate update;
  final CandidateAuditPersistenceDecision persistenceDecision;
  final String? failureMessage;
  final String? diagnosticFailureMessage;

  bool get committed => outcome == CandidateCoordinationOutcome.committed;

  bool get publishable => committed && update.accepted;

  bool get requiresBackfill => update.requiresBackfill;
}

final class RealtimeCandidateCoordinator {
  RealtimeCandidateCoordinator({
    required this.registry,
    required this.auditStore,
    this.metricSink = const NoopCandidateAuditMetricSink(),
  });

  final RealtimeCandidateRegistry registry;
  final CandidateAuditStore auditStore;
  final CandidateAuditMetricSink metricSink;
  final Map<String, Future<void>> _candidateOperationTails = {};

  Future<CandidateCoordinationResult> handle(
    RealtimeObservationEnvelope envelope, {
    RealtimeCandidatePolicy? policy,
  }) {
    final setupId = envelope.setupId;
    final previous = _candidateOperationTails[setupId] ?? Future.value();
    final operation = previous.then(
      (_) => _handleInternal(envelope, policy: policy),
    );
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _candidateOperationTails[setupId] = tail;
    tail.then((_) {
      if (identical(_candidateOperationTails[setupId], tail)) {
        _candidateOperationTails.remove(setupId);
      }
    });
    return operation;
  }

  Future<CandidateCoordinationResult> _handleInternal(
    RealtimeObservationEnvelope envelope, {
    RealtimeCandidatePolicy? policy,
  }) async {
    final prepared = registry.prepare(envelope, policy: policy);
    final update = prepared.update;
    final persistenceDecision = CandidateAuditRetentionPolicy.decide(
      update.auditEvent,
    );

    String? diagnosticFailureMessage;
    if (persistenceDecision == CandidateAuditPersistenceDecision.persist) {
      try {
        await auditStore.append(update.auditEvent);
      } on Object catch (error) {
        return CandidateCoordinationResult(
          outcome: CandidateCoordinationOutcome.durabilityFailed,
          update: update,
          persistenceDecision: persistenceDecision,
          failureMessage: error.toString(),
          diagnosticFailureMessage: null,
        );
      }
    } else if (persistenceDecision ==
        CandidateAuditPersistenceDecision.aggregate) {
      try {
        await metricSink.increment(update.disposition);
      } on Object catch (error) {
        diagnosticFailureMessage = error.toString();
      }
    }

    if (!prepared.requiresCommit) {
      return CandidateCoordinationResult(
        outcome: CandidateCoordinationOutcome.rejected,
        update: update,
        persistenceDecision: persistenceDecision,
        failureMessage: null,
        diagnosticFailureMessage: diagnosticFailureMessage,
      );
    }

    try {
      final committedUpdate = registry.commit(prepared);
      return CandidateCoordinationResult(
        outcome: CandidateCoordinationOutcome.committed,
        update: committedUpdate,
        persistenceDecision: persistenceDecision,
        failureMessage: null,
        diagnosticFailureMessage: diagnosticFailureMessage,
      );
    } on StateError catch (error) {
      return CandidateCoordinationResult(
        outcome: CandidateCoordinationOutcome.commitConflict,
        update: update,
        persistenceDecision: persistenceDecision,
        failureMessage: error.toString(),
        diagnosticFailureMessage: diagnosticFailureMessage,
      );
    }
  }
}
