import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/candidate_audit_codec.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_candidate_audit_store.dart';
import 'package:quantara_app/features/owner_alpha/domain/candidate_audit_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';

void main() {
  group('DurableCandidateAuditStore', () {
    test('appends idempotently and survives a new store instance', () async {
      final storage = _MemoryKeyValueStore();
      final firstStore = DurableCandidateAuditStore(keyValueStore: storage);
      final event = _event(eventId: 'event-1');

      await firstStore.append(event);
      await firstStore.append(_event(eventId: 'event-1', auditSequence: 500));

      final restored = await DurableCandidateAuditStore(
        keyValueStore: storage,
      ).load();
      expect(restored.generation, 1);
      expect(restored.records, hasLength(1));
      expect(restored.records.single.eventId, 'event-1');
    });

    test('selects the highest valid generation across both slots', () async {
      final storage = _MemoryKeyValueStore();
      final store = DurableCandidateAuditStore(keyValueStore: storage);
      final older = CandidateAuditLedger(
        generation: 2,
        records: [CandidateAuditCodec.fromAuditEvent(_event(eventId: 'older'))],
      );
      final newer = CandidateAuditLedger(
        generation: 3,
        records: [CandidateAuditCodec.fromAuditEvent(_event(eventId: 'newer'))],
      );
      storage.values[store.primaryKey] = CandidateAuditCodec.encode(older);
      storage.values[store.backupKey] = CandidateAuditCodec.encode(newer);

      final loaded = await store.load();

      expect(loaded.generation, 3);
      expect(loaded.records.single.eventId, 'newer');
    });

    test('falls back to backup when primary is corrupted', () async {
      final storage = _MemoryKeyValueStore();
      final store = DurableCandidateAuditStore(keyValueStore: storage);
      await store.append(_event(eventId: 'event-1'));
      await store.append(_event(eventId: 'event-2', auditSequence: 2));
      storage.values[store.primaryKey] = '{corrupted';

      final loaded = await store.load();

      expect(loaded.records, hasLength(1));
      expect(loaded.records.single.eventId, 'event-1');
    });

    test(
      'preserves the previous generation when primary write fails',
      () async {
        final storage = _MemoryKeyValueStore();
        final store = DurableCandidateAuditStore(keyValueStore: storage);
        await store.append(_event(eventId: 'event-1'));
        storage.failNextWriteFor = store.primaryKey;

        await expectLater(
          store.append(_event(eventId: 'event-2', auditSequence: 2)),
          throwsStateError,
        );
        final recovered = await store.load();

        expect(recovered.generation, 1);
        expect(recovered.records, hasLength(1));
        expect(recovered.records.single.eventId, 'event-1');
      },
    );

    test('serializes concurrent appends without dropping records', () async {
      final storage = _MemoryKeyValueStore(writeDelay: Duration.zero);
      final store = DurableCandidateAuditStore(
        keyValueStore: storage,
        maximumRecords: 100,
      );

      await Future.wait([
        for (var index = 1; index <= 40; index++)
          store.append(_event(eventId: 'event-$index', auditSequence: index)),
      ]);
      final loaded = await store.load();

      expect(loaded.generation, 40);
      expect(loaded.records, hasLength(40));
      expect(
        loaded.records.map((record) => record.eventId).toSet(),
        hasLength(40),
      );
    });

    test('compacts oldest records at the configured bound', () async {
      final storage = _MemoryKeyValueStore();
      final store = DurableCandidateAuditStore(
        keyValueStore: storage,
        maximumRecords: 3,
      );

      for (var index = 1; index <= 5; index++) {
        await store.append(
          _event(eventId: 'event-$index', auditSequence: index),
        );
      }
      final loaded = await store.load();

      expect(loaded.generation, 5);
      expect(loaded.records.map((record) => record.eventId), [
        'event-3',
        'event-4',
        'event-5',
      ]);
    });

    test('write queue recovers after an operation failure', () async {
      final storage = _MemoryKeyValueStore();
      final store = DurableCandidateAuditStore(keyValueStore: storage);
      storage.failNextWriteFor = store.primaryKey;

      await expectLater(
        store.append(_event(eventId: 'failed')),
        throwsStateError,
      );
      await store.append(_event(eventId: 'recovered', auditSequence: 2));
      final loaded = await store.load();

      expect(loaded.records, hasLength(1));
      expect(loaded.records.single.eventId, 'recovered');
    });
  });
}

final class _MemoryKeyValueStore implements CandidateAuditKeyValueStore {
  _MemoryKeyValueStore({this.writeDelay = Duration.zero});

  final Duration writeDelay;
  final Map<String, String> values = {};
  String? failNextWriteFor;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    if (failNextWriteFor == key) {
      failNextWriteFor = null;
      throw StateError('injected write failure');
    }
    values[key] = value;
  }
}

CandidateRegistryAuditEvent _event({
  required String eventId,
  int auditSequence = 1,
}) => CandidateRegistryAuditEvent(
  auditSequence: auditSequence,
  disposition: StreamEventDisposition.accepted,
  eventId: eventId,
  setupId: 'BTCUSDT|1h|long|audit',
  streamKey: RealtimeStreamKey(symbol: 'BTCUSDT', timeframe: '1h'),
  observedAtUtc: DateTime.utc(
    2026,
    8,
    2,
    12,
  ).add(Duration(seconds: auditSequence)),
  previousStage: OpportunityStage.detected,
  currentStage: OpportunityStage.armed,
  transitionReason: OpportunityTransitionReason.entryApproaching,
  gap: null,
);
