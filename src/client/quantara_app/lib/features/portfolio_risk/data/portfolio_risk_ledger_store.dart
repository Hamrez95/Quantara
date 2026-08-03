import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../domain/portfolio_risk_models.dart';

abstract interface class PortfolioRiskLedgerStore {
  Future<PortfolioRiskLedger?> load();

  Future<void> save(PortfolioRiskLedger ledger);
}

final class DatabasePortfolioRiskLedgerStore
    implements PortfolioRiskLedgerStore {
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
    final existing = await database.read(
      QuantaraDurableCategory.managedPositions,
      _recordKey,
    );
    if (existing != null) {
      final current = PortfolioRiskLedger.fromJson(existing.payload);
      if (current.revision > ledger.revision) {
        throw StateError('Portfolio risk ledger revision moved backwards.');
      }
      if (current.revision == ledger.revision) {
        if (current.toJson().toString() == ledger.toJson().toString()) return;
        throw StateError('Conflicting portfolio risk ledger revision.');
      }
    }
    await database.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.managedPositions,
        key: _recordKey,
        schemaVersion: ledger.schemaVersion,
        revision: (existing?.revision ?? 0) + 1,
        updatedAt: DateTime.now().toUtc(),
        payload: ledger.toJson(),
      ),
    );
  }
}
