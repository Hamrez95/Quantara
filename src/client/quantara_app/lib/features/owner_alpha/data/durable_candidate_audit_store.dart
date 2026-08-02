import '../domain/candidate_audit_models.dart';
import '../domain/realtime_market_event_models.dart';
import 'candidate_audit_codec.dart';

abstract interface class CandidateAuditKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

final class DurableCandidateAuditStore implements CandidateAuditStore {
  DurableCandidateAuditStore({
    required CandidateAuditKeyValueStore keyValueStore,
    this.maximumRecords = 2000,
    this.primaryKey = 'quantara.candidate-audit.primary-v1',
    this.backupKey = 'quantara.candidate-audit.backup-v1',
  }) : _keyValueStore = keyValueStore {
    if (maximumRecords < 1) {
      throw ArgumentError.value(maximumRecords, 'maximumRecords');
    }
    if (primaryKey.trim().isEmpty || backupKey.trim().isEmpty) {
      throw ArgumentError('Candidate audit storage keys must not be empty.');
    }
    if (primaryKey == backupKey) {
      throw ArgumentError('Primary and backup audit keys must differ.');
    }
  }

  final CandidateAuditKeyValueStore _keyValueStore;
  final int maximumRecords;
  final String primaryKey;
  final String backupKey;
  Future<void> _writeTail = Future.value();

  @override
  Future<CandidateAuditLedger> load() async {
    final primary = CandidateAuditCodec.tryDecode(
      await _keyValueStore.read(primaryKey),
    );
    final backup = CandidateAuditCodec.tryDecode(
      await _keyValueStore.read(backupKey),
    );
    if (primary == null && backup == null) {
      return CandidateAuditLedger.empty();
    }
    if (primary == null) return backup!;
    if (backup == null) return primary;
    return primary.generation >= backup.generation ? primary : backup;
  }

  @override
  Future<void> append(CandidateRegistryAuditEvent event) {
    final operation = _writeTail.then((_) => _appendInternal(event));
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _appendInternal(CandidateRegistryAuditEvent event) async {
    final current = await load();
    final record = CandidateAuditCodec.fromAuditEvent(event);
    final next = current.append(record, maximumRecords: maximumRecords);
    if (identical(next, current)) return;

    await _keyValueStore.write(backupKey, CandidateAuditCodec.encode(current));
    await _keyValueStore.write(primaryKey, CandidateAuditCodec.encode(next));
  }
}
