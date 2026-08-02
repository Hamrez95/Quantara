import 'realtime_candidate_models.dart';
import 'realtime_market_event_models.dart';

final class CandidateAuditRecord {
  CandidateAuditRecord({
    required this.recordId,
    required this.auditSequence,
    required this.disposition,
    required this.eventId,
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.observedAtUtc,
    required this.previousStage,
    required this.currentStage,
    required this.transitionReason,
    required this.expectedSequence,
    required this.observedSequence,
  }) {
    validate();
  }

  final String recordId;
  final int auditSequence;
  final StreamEventDisposition disposition;
  final String eventId;
  final String setupId;
  final String symbol;
  final String timeframe;
  final DateTime observedAtUtc;
  final OpportunityStage? previousStage;
  final OpportunityStage? currentStage;
  final OpportunityTransitionReason? transitionReason;
  final int? expectedSequence;
  final int? observedSequence;

  bool get hasGap => expectedSequence != null && observedSequence != null;

  void validate() {
    _validateIdentifier(recordId, 'recordId', maximumLength: 128);
    _validateIdentifier(eventId, 'eventId');
    _validateIdentifier(setupId, 'setupId');
    _validateIdentifier(symbol, 'symbol', maximumLength: 40);
    _validateIdentifier(timeframe, 'timeframe', maximumLength: 20);
    if (auditSequence < 1) {
      throw ArgumentError.value(auditSequence, 'auditSequence');
    }
    if (!observedAtUtc.isUtc) {
      throw ArgumentError.value(
        observedAtUtc,
        'observedAtUtc',
        'UTC is required.',
      );
    }
    if ((expectedSequence == null) != (observedSequence == null)) {
      throw ArgumentError(
        'Gap sequence values must either both be present or both be absent.',
      );
    }
    if (hasGap) {
      if (disposition != StreamEventDisposition.gapDetected ||
          expectedSequence! < 0 ||
          observedSequence! <= expectedSequence!) {
        throw ArgumentError('The persisted stream gap is invalid.');
      }
    } else if (disposition == StreamEventDisposition.gapDetected) {
      throw ArgumentError('A gap disposition requires sequence details.');
    }
  }

  static void _validateIdentifier(
    String value,
    String name, {
    int maximumLength = 320,
  }) {
    if (value.trim().isEmpty || value.length > maximumLength) {
      throw ArgumentError.value(value, name);
    }
  }
}

final class CandidateAuditLedger {
  CandidateAuditLedger({
    required this.generation,
    required Iterable<CandidateAuditRecord> records,
  }) : records = List.unmodifiable(records) {
    if (generation < 0) {
      throw ArgumentError.value(generation, 'generation');
    }
    final identifiers = <String>{};
    for (final record in this.records) {
      record.validate();
      if (!identifiers.add(record.recordId)) {
        throw ArgumentError('Duplicate candidate audit record identifier.');
      }
    }
  }

  factory CandidateAuditLedger.empty() =>
      CandidateAuditLedger(generation: 0, records: const []);

  final int generation;
  final List<CandidateAuditRecord> records;

  bool contains(String recordId) =>
      records.any((record) => record.recordId == recordId);

  CandidateAuditLedger append(
    CandidateAuditRecord record, {
    required int maximumRecords,
  }) {
    if (maximumRecords < 1) {
      throw ArgumentError.value(maximumRecords, 'maximumRecords');
    }
    if (contains(record.recordId)) return this;

    final nextRecords = <CandidateAuditRecord>[...records, record];
    final overflow = nextRecords.length - maximumRecords;
    return CandidateAuditLedger(
      generation: generation + 1,
      records: overflow > 0 ? nextRecords.sublist(overflow) : nextRecords,
    );
  }
}

abstract interface class CandidateAuditStore {
  Future<CandidateAuditLedger> load();

  Future<void> append(CandidateRegistryAuditEvent event);
}
