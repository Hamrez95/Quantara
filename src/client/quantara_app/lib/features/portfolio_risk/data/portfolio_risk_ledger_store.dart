import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
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

final class DatabasePortfolioRiskLedgerStore
    implements PortfolioRiskLedgerStore, AtomicPortfolioRiskLedgerStore {
  DatabasePortfolioRiskLedgerStore({
    Future<QuantaraDurableDatabase> Function()? databaseFactory,
  }) : _databaseFactory =
           databaseFactory ?? (() => QuantaraDatabaseProvider.instance);

  static const _recordKey = 'portfolio-risk-ledger-v1';
  final Future<QuantaraDurableDatabase> Function() _databaseFactory;

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
    if (existing != null) {
      final current = PortfolioRiskLedger.fromJson(existing.payload);
      _validateProgress(current: current, incoming: ledger);
      if (_sameLedger(current, ledger)) return;
    }
    await database.put(_recordFor(ledger, (existing?.revision ?? 0) + 1));
  }

  @override
  Future<T> mutate<T>(PortfolioRiskLedgerMutator<T> mutation) async {
    final database = await _databaseFactory();
    if (database is! QuantaraAtomicDurableDatabase) {
      throw StateError(
        'Portfolio risk mutation requires an atomic durable database.',
      );
    }
    return database.mutateRecord<T>(
      category: QuantaraDurableCategory.managedPositions,
      key: _recordKey,
      mutation: (currentRecord) async {
        final current = currentRecord == null
            ? null
            : PortfolioRiskLedger.fromJson(currentRecord.payload);
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
          nextRecord: _recordFor(next, (currentRecord?.revision ?? 0) + 1),
        );
      },
    );
  }

  static QuantaraDurableRecord _recordFor(
    PortfolioRiskLedger ledger,
    int durableRevision,
  ) => QuantaraDurableRecord(
    category: QuantaraDurableCategory.managedPositions,
    key: _recordKey,
    schemaVersion: ledger.schemaVersion,
    revision: durableRevision,
    updatedAt: DateTime.now().toUtc(),
    payload: ledger.toJson(),
  );

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
  ) => left.toJson().toString() == right.toJson().toString();
}
