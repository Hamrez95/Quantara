import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/candidate_audit_codec.dart';
import 'package:quantara_app/features/owner_alpha/domain/candidate_audit_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';

void main() {
  group('CandidateAuditCodec', () {
    test('round trips accepted and gap audit records', () {
      final accepted = CandidateAuditCodec.fromAuditEvent(
        _event(eventId: 'accepted-1'),
      );
      final gap = CandidateAuditCodec.fromAuditEvent(
        _event(
          eventId: 'gap-1',
          auditSequence: 2,
          disposition: StreamEventDisposition.gapDetected,
          previousStage: OpportunityStage.armed,
          currentStage: OpportunityStage.armed,
          transitionReason: null,
          gap: const RealtimeStreamGap(
            expectedSequence: 7,
            observedSequence: 10,
          ),
        ),
      );
      final ledger = CandidateAuditLedger(
        generation: 4,
        records: [accepted, gap],
      );

      final decoded = CandidateAuditCodec.tryDecode(
        CandidateAuditCodec.encode(ledger),
      );

      expect(decoded, isNotNull);
      expect(decoded?.generation, 4);
      expect(decoded?.records, hasLength(2));
      expect(decoded?.records.first.disposition, StreamEventDisposition.accepted);
      expect(decoded?.records.last.expectedSequence, 7);
      expect(decoded?.records.last.observedSequence, 10);
    });

    test('record identifier is stable across local audit sequence changes', () {
      final first = CandidateAuditCodec.fromAuditEvent(
        _event(eventId: 'stable', auditSequence: 1),
      );
      final afterRestart = CandidateAuditCodec.fromAuditEvent(
        _event(eventId: 'stable', auditSequence: 900),
      );

      expect(first.recordId, afterRestart.recordId);
      expect(first.auditSequence, isNot(afterRestart.auditSequence));
    });

    test('rejects tampered checksum and unsupported schema', () {
      final encoded = CandidateAuditCodec.encode(
        CandidateAuditLedger(
          generation: 1,
          records: [
            CandidateAuditCodec.fromAuditEvent(_event(eventId: 'event-1')),
          ],
        ),
      );
      final envelope = jsonDecode(encoded) as Map<String, Object?>;
      final body = Map<String, Object?>.from(
        envelope['body']! as Map<String, Object?>,
      );
      body['generation'] = 99;
      final tampered = jsonEncode({...envelope, 'body': body});
      expect(CandidateAuditCodec.tryDecode(tampered), isNull);

      final unsupportedBody = <String, Object?>{
        ...body,
        'schemaVersion': CandidateAuditCodec.schemaVersion + 1,
      };
      final unsupported = jsonEncode({
        'body': unsupportedBody,
        'checksum': envelope['checksum'],
      });
      expect(CandidateAuditCodec.tryDecode(unsupported), isNull);
    });

    test('rejects malformed gap and duplicate record identifiers', () {
      expect(
        () => CandidateAuditRecord(
          recordId: 'record',
          auditSequence: 1,
          disposition: StreamEventDisposition.gapDetected,
          eventId: 'event',
          setupId: 'setup',
          symbol: 'BTCUSDT',
          timeframe: '1h',
          observedAtUtc: DateTime.utc(2026, 8, 2),
          previousStage: OpportunityStage.armed,
          currentStage: OpportunityStage.armed,
          transitionReason: null,
          expectedSequence: null,
          observedSequence: null,
        ),
        throwsArgumentError,
      );

      final record = CandidateAuditCodec.fromAuditEvent(
        _event(eventId: 'duplicate'),
      );
      expect(
        () => CandidateAuditLedger(
          generation: 1,
          records: [record, record],
        ),
        throwsArgumentError,
      );
    });
  });
}

CandidateRegistryAuditEvent _event({
  required String eventId,
  int auditSequence = 1,
  StreamEventDisposition disposition = StreamEventDisposition.accepted,
  OpportunityStage? previousStage = OpportunityStage.detected,
  OpportunityStage? currentStage = OpportunityStage.armed,
  OpportunityTransitionReason? transitionReason =
      OpportunityTransitionReason.entryApproaching,
  RealtimeStreamGap? gap,
}) => CandidateRegistryAuditEvent(
  auditSequence: auditSequence,
  disposition: disposition,
  eventId: eventId,
  setupId: 'BTCUSDT|1h|long|audit',
  streamKey: RealtimeStreamKey(symbol: 'BTCUSDT', timeframe: '1h'),
  observedAtUtc: DateTime.utc(2026, 8, 2, 12, auditSequence),
  previousStage: previousStage,
  currentStage: currentStage,
  transitionReason: transitionReason,
  gap: gap,
);
