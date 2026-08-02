import 'dart:collection';

import '../domain/realtime_candidate_models.dart';
import '../domain/realtime_market_event_models.dart';
import 'realtime_candidate_engine.dart';

typedef RealtimeCandidatePolicyResolver =
    RealtimeCandidatePolicy Function(RealtimeOpportunityCandidate candidate);

final class CandidateRegistryPreparedUpdate {
  CandidateRegistryPreparedUpdate._({
    required this.update,
    required this.requiresCommit,
    required this._owner,
    required this._candidateRevision,
    required this._candidateSetupId,
    required this._nextCandidate,
    required this._cursorKey,
    required this._nextCursor,
    required this._deduplicationKey,
  });

  final CandidateRegistryUpdate update;
  final bool requiresCommit;
  final RealtimeCandidateRegistry _owner;
  final int _candidateRevision;
  final String? _candidateSetupId;
  final RealtimeOpportunityCandidate? _nextCandidate;
  final _CandidateStreamKey? _cursorKey;
  final _StreamCursor? _nextCursor;
  final String? _deduplicationKey;
}

final class RealtimeCandidateRegistry {
  RealtimeCandidateRegistry({
    this.maximumCandidates = 2000,
    this.recentEventCapacity = 4096,
    RealtimeCandidatePolicyResolver? policyResolver,
  }) : _policyResolver = policyResolver ?? _balancedPolicy {
    if (maximumCandidates < 1) {
      throw ArgumentError.value(maximumCandidates, 'maximumCandidates');
    }
    if (recentEventCapacity < 1) {
      throw ArgumentError.value(recentEventCapacity, 'recentEventCapacity');
    }
  }

  final int maximumCandidates;
  final int recentEventCapacity;
  final RealtimeCandidatePolicyResolver _policyResolver;
  final Map<String, RealtimeOpportunityCandidate> _candidates = {};
  final Map<String, int> _candidateRevisions = {};
  final Map<_CandidateStreamKey, _StreamCursor> _streamCursors = {};
  final LinkedHashSet<String> _recentEventIds = LinkedHashSet();
  var _nextAuditSequence = 1;

  int get candidateCount => _candidates.length;

  int revisionFor(String setupId) => _candidateRevisions[setupId] ?? -1;

  RealtimeOpportunityCandidate? candidateFor(String setupId) =>
      _candidates[setupId];

  List<RealtimeOpportunityCandidate> get openDiscoveryCandidates {
    final result = _candidates.values
        .where((candidate) => !candidate.isClosedForDiscovery)
        .toList(growable: false);
    result.sort(
      (left, right) => right.lastUpdatedAtUtc.compareTo(left.lastUpdatedAtUtc),
    );
    return List.unmodifiable(result);
  }

  CandidateRegistrationResult register(RealtimeOpportunityCandidate candidate) {
    final existing = _candidates[candidate.setupId];
    if (existing != null) {
      return CandidateRegistrationResult(
        disposition: _sameIdentity(existing, candidate)
            ? CandidateRegistrationDisposition.alreadyRegistered
            : CandidateRegistrationDisposition.conflict,
        candidate: existing,
      );
    }
    if (_candidates.length >= maximumCandidates) {
      return const CandidateRegistrationResult(
        disposition: CandidateRegistrationDisposition.capacityExceeded,
        candidate: null,
      );
    }

    _candidates[candidate.setupId] = candidate;
    _candidateRevisions[candidate.setupId] = 0;
    return CandidateRegistrationResult(
      disposition: CandidateRegistrationDisposition.registered,
      candidate: candidate,
    );
  }

  CandidateRegistryPreparedUpdate prepare(
    RealtimeObservationEnvelope envelope, {
    RealtimeCandidatePolicy? policy,
  }) {
    final candidate = _candidates[envelope.setupId];
    if (candidate == null) {
      return _rejectedPreparation(
        envelope: envelope,
        disposition: StreamEventDisposition.unknownCandidate,
      );
    }
    if (candidate.symbol != envelope.symbol ||
        candidate.timeframe != envelope.timeframe) {
      return _rejectedPreparation(
        envelope: envelope,
        disposition: StreamEventDisposition.identityMismatch,
        candidate: candidate,
      );
    }
    if (_recentEventIds.contains(envelope.deduplicationKey)) {
      return _rejectedPreparation(
        envelope: envelope,
        disposition: StreamEventDisposition.duplicate,
        candidate: candidate,
      );
    }

    final cursorKey = _CandidateStreamKey(
      setupId: envelope.setupId,
      streamKey: envelope.streamKey,
    );
    final cursor = _streamCursors[cursorKey];
    final sequence = envelope.sequence;
    if (sequence != null && cursor?.sequence != null) {
      if (sequence <= cursor!.sequence!) {
        return _rejectedPreparation(
          envelope: envelope,
          disposition: StreamEventDisposition.outOfOrder,
          candidate: candidate,
        );
      }
      final expected = cursor.sequence! + 1;
      if (sequence > expected) {
        return _rejectedPreparation(
          envelope: envelope,
          disposition: StreamEventDisposition.gapDetected,
          candidate: candidate,
          gap: RealtimeStreamGap(
            expectedSequence: expected,
            observedSequence: sequence,
          ),
        );
      }
    } else if (cursor != null &&
        envelope.observation.exchangeTimestampUtc.isBefore(
          cursor.exchangeTimestampUtc,
        )) {
      return _rejectedPreparation(
        envelope: envelope,
        disposition: StreamEventDisposition.outOfOrder,
        candidate: candidate,
      );
    }

    final evaluation = RealtimeCandidateEngine.evaluate(
      candidate: candidate,
      observation: envelope.observation,
      policy: policy ?? _policyResolver(candidate),
    );
    final update = CandidateRegistryUpdate(
      disposition: StreamEventDisposition.accepted,
      candidate: evaluation.candidate,
      evaluation: evaluation,
      auditEvent: _audit(
        envelope: envelope,
        disposition: StreamEventDisposition.accepted,
        previousStage: evaluation.previousStage,
        currentStage: evaluation.candidate.stage,
        transitionReason: evaluation.candidate.transitionReason,
      ),
    );

    return CandidateRegistryPreparedUpdate._(
      update: update,
      requiresCommit: true,
      _owner: this,
      _candidateRevision: revisionFor(candidate.setupId),
      _candidateSetupId: candidate.setupId,
      _nextCandidate: evaluation.candidate,
      _cursorKey: cursorKey,
      _nextCursor: _StreamCursor(
        sequence: sequence ?? cursor?.sequence,
        exchangeTimestampUtc: envelope.observation.exchangeTimestampUtc,
      ),
      _deduplicationKey: envelope.deduplicationKey,
    );
  }

  CandidateRegistryUpdate commit(CandidateRegistryPreparedUpdate prepared) {
    if (!identical(prepared._owner, this)) {
      throw ArgumentError('The prepared update belongs to another registry.');
    }
    if (!prepared.requiresCommit) return prepared.update;

    final setupId = prepared._candidateSetupId;
    final nextCandidate = prepared._nextCandidate;
    final cursorKey = prepared._cursorKey;
    final nextCursor = prepared._nextCursor;
    final deduplicationKey = prepared._deduplicationKey;
    if (setupId == null ||
        nextCandidate == null ||
        cursorKey == null ||
        nextCursor == null ||
        deduplicationKey == null) {
      throw StateError('The prepared candidate update is incomplete.');
    }
    if (prepared._candidateRevision != revisionFor(setupId)) {
      throw StateError(
        'The candidate changed after this update was prepared.',
      );
    }

    _candidates[setupId] = nextCandidate;
    _streamCursors[cursorKey] = nextCursor;
    _remember(deduplicationKey);
    _candidateRevisions[setupId] = prepared._candidateRevision + 1;
    return prepared.update;
  }

  CandidateRegistryUpdate apply(
    RealtimeObservationEnvelope envelope, {
    RealtimeCandidatePolicy? policy,
  }) {
    final prepared = prepare(envelope, policy: policy);
    return prepared.requiresCommit ? commit(prepared) : prepared.update;
  }

  void markReconciled({
    required String setupId,
    required RealtimeStreamKey streamKey,
    required DateTime exchangeTimestampUtc,
    int? sequence,
  }) {
    final candidate = _candidates[setupId];
    if (candidate == null) {
      throw ArgumentError.value(setupId, 'setupId', 'Candidate not found.');
    }
    if (candidate.symbol != streamKey.symbol ||
        candidate.timeframe != streamKey.timeframe) {
      throw ArgumentError(
        'The reconciliation stream identity does not match the candidate.',
      );
    }
    if (!exchangeTimestampUtc.isUtc) {
      throw ArgumentError.value(
        exchangeTimestampUtc,
        'exchangeTimestampUtc',
        'UTC is required.',
      );
    }
    if (sequence != null && sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence');
    }

    final cursorKey = _CandidateStreamKey(
      setupId: setupId,
      streamKey: streamKey,
    );
    final existing = _streamCursors[cursorKey];
    if (existing != null) {
      if (exchangeTimestampUtc.isBefore(existing.exchangeTimestampUtc)) {
        throw ArgumentError(
          'The reconciliation timestamp cannot move the cursor backwards.',
        );
      }
      if (sequence != null &&
          existing.sequence != null &&
          sequence < existing.sequence!) {
        throw ArgumentError(
          'The reconciliation sequence cannot move the cursor backwards.',
        );
      }
    }

    _streamCursors[cursorKey] = _StreamCursor(
      sequence: sequence,
      exchangeTimestampUtc: exchangeTimestampUtc,
    );
    _candidateRevisions[setupId] = revisionFor(setupId) + 1;
  }

  CandidateRegistryPreparedUpdate _rejectedPreparation({
    required RealtimeObservationEnvelope envelope,
    required StreamEventDisposition disposition,
    RealtimeOpportunityCandidate? candidate,
    RealtimeStreamGap? gap,
  }) => CandidateRegistryPreparedUpdate._(
    update: CandidateRegistryUpdate(
      disposition: disposition,
      candidate: candidate,
      evaluation: null,
      auditEvent: _audit(
        envelope: envelope,
        disposition: disposition,
        previousStage: candidate?.stage,
        currentStage: candidate?.stage,
        transitionReason: null,
        gap: gap,
      ),
    ),
    requiresCommit: false,
    _owner: this,
    _candidateRevision: candidate == null
        ? -1
        : revisionFor(candidate.setupId),
    _candidateSetupId: null,
    _nextCandidate: null,
    _cursorKey: null,
    _nextCursor: null,
    _deduplicationKey: null,
  );

  CandidateRegistryAuditEvent _audit({
    required RealtimeObservationEnvelope envelope,
    required StreamEventDisposition disposition,
    required OpportunityStage? previousStage,
    required OpportunityStage? currentStage,
    required OpportunityTransitionReason? transitionReason,
    RealtimeStreamGap? gap,
  }) => CandidateRegistryAuditEvent(
    auditSequence: _nextAuditSequence++,
    disposition: disposition,
    eventId: envelope.eventId,
    setupId: envelope.setupId,
    streamKey: envelope.streamKey,
    observedAtUtc: envelope.observation.evaluatedAtUtc,
    previousStage: previousStage,
    currentStage: currentStage,
    transitionReason: transitionReason,
    gap: gap,
  );

  void _remember(String deduplicationKey) {
    _recentEventIds.remove(deduplicationKey);
    _recentEventIds.add(deduplicationKey);
    while (_recentEventIds.length > recentEventCapacity) {
      _recentEventIds.remove(_recentEventIds.first);
    }
  }

  static RealtimeCandidatePolicy _balancedPolicy(
    RealtimeOpportunityCandidate candidate,
  ) => RealtimeCandidatePolicy.balanced;

  static bool _sameIdentity(
    RealtimeOpportunityCandidate left,
    RealtimeOpportunityCandidate right,
  ) =>
      left.setupId == right.setupId &&
      left.symbol == right.symbol &&
      left.timeframe == right.timeframe &&
      left.playbookId == right.playbookId &&
      left.direction == right.direction &&
      left.entryLower == right.entryLower &&
      left.entryUpper == right.entryUpper &&
      left.invalidationPrice == right.invalidationPrice &&
      left.validUntilUtc == right.validUntilUtc &&
      left.detectedAtUtc == right.detectedAtUtc;
}

final class _CandidateStreamKey {
  const _CandidateStreamKey({required this.setupId, required this.streamKey});

  final String setupId;
  final RealtimeStreamKey streamKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CandidateStreamKey &&
          setupId == other.setupId &&
          streamKey == other.streamKey;

  @override
  int get hashCode => Object.hash(setupId, streamKey);
}

final class _StreamCursor {
  const _StreamCursor({
    required this.sequence,
    required this.exchangeTimestampUtc,
  });

  final int? sequence;
  final DateTime exchangeTimestampUtc;
}
