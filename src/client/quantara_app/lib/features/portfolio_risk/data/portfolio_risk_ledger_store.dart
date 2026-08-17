import 'dart:convert';

import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../domain/capital_guardian.dart';
import '../domain/portfolio_risk_models.dart';

abstract interface class PortfolioRiskLedgerStore {
  Future<PortfolioRiskLedger?> load();

  Future<void> save(PortfolioRiskLedger ledger);
}

final class PortfolioRiskLedgerMutation<T> {
  const PortfolioRiskLedgerMutation({required this.value, this.nextLedger});

  final T value;
  final PortfolioRiskLedger? nextLedger;
}

typedef PortfolioRiskLedgerMutator<T> =
    Future<PortfolioRiskLedgerMutation<T>> Function(
      PortfolioRiskLedger? current,
    );

abstract interface class AtomicPortfolioRiskLedgerStore {
  Future<T> mutate<T>(PortfolioRiskLedgerMutator<T> mutation);
}

abstract interface class CapitalGuardianStateStore {
  Future<CapitalGuardianState?> loadCapitalGuardian();
}

final class PortfolioRiskAndGuardianMutation<T> {
  const PortfolioRiskAndGuardianMutation({
    required this.value,
    this.nextLedger,
    this.nextGuardian,
  });

  final T value;
  final PortfolioRiskLedger? nextLedger;
  final CapitalGuardianState? nextGuardian;
}

typedef PortfolioRiskAndGuardianMutator<T> =
    Future<PortfolioRiskAndGuardianMutation<T>> Function(
      PortfolioRiskLedger? current,
      CapitalGuardianState? guardian,
    );

abstract interface class AtomicPortfolioRiskAndGuardianStore {
  Future<T> mutateRiskAndGuardian<T>(
    PortfolioRiskAndGuardianMutator<T> mutation,
  );
}

final class DatabasePortfolioRiskLedgerStore
    implements
        PortfolioRiskLedgerStore,
        AtomicPortfolioRiskLedgerStore,
        CapitalGuardianStateStore,
        AtomicPortfolioRiskAndGuardianStore {
  DatabasePortfolioRiskLedgerStore({
    Future<QuantaraDurableDatabase> Function()? databaseFactory,
    String recordKey = defaultRecordKey,
  }) : _databaseFactory =
           databaseFactory ?? (() => QuantaraDatabaseProvider.instance),
       _recordKey = _validatedRecordKey(recordKey);

  static const defaultRecordKey = 'portfolio-risk-ledger-v1';
  static const _guardianPayloadKey = 'capitalGuardian';
  final Future<QuantaraDurableDatabase> Function() _databaseFactory;
  final String _recordKey;

  static String _validatedRecordKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 120) {
      throw const FormatException('Portfolio risk record key is invalid.');
    }
    return normalized;
  }

  @override
  Future<PortfolioRiskLedger?> load() async {
    final database = await _databaseFactory();
    final record = await database.read(
      QuantaraDurableCategory.managedPositions,
      _recordKey,
    );
    if (record == null) return null;
    return PortfolioRiskLedger.fromJson(record.payload);
  }

  @override
  Future<CapitalGuardianState?> loadCapitalGuardian() async {
    final database = await _databaseFactory();
    final record = await database.read(
      QuantaraDurableCategory.managedPositions,
      _recordKey,
    );
    if (record == null) return null;
    return _guardianFromPayload(record.payload);
  }

  @override
  Future<void> save(PortfolioRiskLedger ledger) async {
    final database = await _databaseFactory();
    if (database is QuantaraAtomicDurableDatabase) {
      await mutate<void>((current) async {
        if (current != null) {
          _validateProgress(current: current, incoming: ledger);
          if (_sameLedger(current, ledger)) {
            return const PortfolioRiskLedgerMutation<void>(value: null);
          }
        }
        return PortfolioRiskLedgerMutation<void>(
          value: null,
          nextLedger: ledger,
        );
      });
      return;
    }

    final existing = await database.read(
      QuantaraDurableCategory.managedPositions,
      _recordKey,
    );
    CapitalGuardianState? guardian;
    if (existing != null) {
      final current = PortfolioRiskLedger.fromJson(existing.payload);
      guardian = _guardianFromPayload(existing.payload);
      _validateProgress(current: current, incoming: ledger);
      if (_sameLedger(current, ledger)) return;
    }
    await database.put(
      _recordFor(ledger, (existing?.revision ?? 0) + 1, guardian: guardian),
    );
  }

  @override
  Future<T> mutate<T>(PortfolioRiskLedgerMutator<T> mutation) async {
    final database = await _databaseFactory();
    if (database is! QuantaraAtomicDurableDatabase) {
      throw StateError(
        'Portfolio risk mutation requires an atomic durable database.',
      );
    }
    final atomicDatabase = database as QuantaraAtomicDurableDatabase;
    return atomicDatabase.mutateRecord<T>(
      category: QuantaraDurableCategory.managedPositions,
      key: _recordKey,
      mutation: (currentRecord) async {
        final current = currentRecord == null
            ? null
            : PortfolioRiskLedger.fromJson(currentRecord.payload);
        final guardian = currentRecord == null
            ? null
            : _guardianFromPayload(currentRecord.payload);
        final result = await mutation(current);
        final next = result.nextLedger;
        if (next == null) {
          return QuantaraAtomicRecordMutation<T>(value: result.value);
        }
        if (current != null) {
          _validateProgress(current: current, incoming: next);
          if (_sameLedger(current, next)) {
            return QuantaraAtomicRecordMutation<T>(value: result.value);
          }
        }
        return QuantaraAtomicRecordMutation<T>(
          value: result.value,
          nextRecord: _recordFor(
            next,
            (currentRecord?.revision ?? 0) + 1,
            guardian: guardian,
          ),
        );
      },
    );
  }

  @override
  Future<T> mutateRiskAndGuardian<T>(
    PortfolioRiskAndGuardianMutator<T> mutation,
  ) async {
    final database = await _databaseFactory();
    if (database is! QuantaraAtomicDurableDatabase) {
      throw StateError(
        'Capital Guardian mutation requires an atomic durable database.',
      );
    }
    final atomicDatabase = database as QuantaraAtomicDurableDatabase;
    return atomicDatabase.mutateRecord<T>(
      category: QuantaraDurableCategory.managedPositions,
      key: _recordKey,
      mutation: (currentRecord) async {
        final currentLedger = currentRecord == null
            ? null
            : PortfolioRiskLedger.fromJson(currentRecord.payload);
        final currentGuardian = currentRecord == null
            ? null
            : _guardianFromPayload(currentRecord.payload);
        final result = await mutation(currentLedger, currentGuardian);
        final nextLedger = result.nextLedger ?? currentLedger;
        final nextGuardian = result.nextGuardian ?? currentGuardian;
        if (nextLedger == null) {
          throw StateError(
            'Capital Guardian state cannot persist before risk ledger initialization.',
          );
        }
        if (currentLedger != null && result.nextLedger != null) {
          _validateProgress(current: currentLedger, incoming: nextLedger);
        }
        final ledgerChanged =
            currentLedger == null || !_sameLedger(currentLedger, nextLedger);
        final guardianChanged = !_sameGuardian(currentGuardian, nextGuardian);
        if (!ledgerChanged && !guardianChanged) {
          return QuantaraAtomicRecordMutation<T>(value: result.value);
        }
        return QuantaraAtomicRecordMutation<T>(
          value: result.value,
          nextRecord: _recordFor(
            nextLedger,
            (currentRecord?.revision ?? 0) + 1,
            guardian: nextGuardian,
          ),
        );
      },
    );
  }

  QuantaraDurableRecord _recordFor(
    PortfolioRiskLedger ledger,
    int durableRevision, {
    CapitalGuardianState? guardian,
  }) => QuantaraDurableRecord(
    category: QuantaraDurableCategory.managedPositions,
    key: _recordKey,
    schemaVersion: ledger.schemaVersion,
    revision: durableRevision,
    updatedAt: DateTime.now().toUtc(),
    payload: <String, Object?>{
      ...ledger.toJson(),
      if (guardian != null) _guardianPayloadKey: guardian.toJson(),
    },
  );

  static CapitalGuardianState? _guardianFromPayload(
    Map<String, Object?> payload,
  ) {
    final raw = payload[_guardianPayloadKey];
    if (raw == null) return null;
    if (raw is! Map<Object?, Object?>) {
      throw const FormatException('Capital Guardian payload is invalid.');
    }
    return CapitalGuardianState.fromJson(<String, Object?>{
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    });
  }

  static void _validateProgress({
    required PortfolioRiskLedger current,
    required PortfolioRiskLedger incoming,
  }) {
    if (current.revision > incoming.revision) {
      throw StateError('Portfolio risk ledger revision moved backwards.');
    }
    if (current.revision == incoming.revision &&
        !_sameLedger(current, incoming)) {
      throw StateError('Conflicting portfolio risk ledger revision.');
    }
  }

  static bool _sameLedger(
    PortfolioRiskLedger left,
    PortfolioRiskLedger right,
  ) => _canonicalJson(left.toJson()) == _canonicalJson(right.toJson());

  static bool _sameGuardian(
    CapitalGuardianState? left,
    CapitalGuardianState? right,
  ) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return _canonicalJson(left.toJson()) == _canonicalJson(right.toJson());
  }

  static String _canonicalJson(Object? value) {
    Object? normalize(Object? input) {
      if (input is Map<Object?, Object?>) {
        final keys = input.keys.map((key) => key.toString()).toList()..sort();
        return <String, Object?>{
          for (final key in keys) key: normalize(input[key]),
        };
      }
      if (input is Iterable<Object?>) {
        return input.map(normalize).toList(growable: false);
      }
      return input;
    }

    return jsonEncode(normalize(value));
  }
}
