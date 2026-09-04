import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_lab_models.dart';

/// Stable Trading Lab identity for one exact strategy implementation snapshot.
///
/// New evaluation runs prefer the versioned registry identity introduced for
/// Local Live. Legacy runs remain readable through the historical
/// `strategy@version` representation, but new exact evaluations never silently
/// collapse different parameter snapshots into the same bucket.
String tradingLabStrategyIdentityKey(TradeIdea idea) {
  final registryId = idea.registryStrategyId.trim();
  final registryVersion = idea.registryStrategyVersion.trim();
  final snapshotHash = idea.strategySnapshotHash.trim();
  final managementPolicy = idea.managementPolicyVersion.trim();
  final implementationVersion = idea.strategyImplementationVersion.trim();
  final schemaVersion = idea.strategyParameterSchemaVersion;

  if (registryId.isNotEmpty &&
      registryVersion.isNotEmpty &&
      snapshotHash.isNotEmpty &&
      managementPolicy.isNotEmpty &&
      implementationVersion.isNotEmpty &&
      schemaVersion > 0) {
    return <String>[
      'registry:$registryId@$registryVersion',
      'schema:$schemaVersion',
      'snapshot:$snapshotHash',
      'policy:$managementPolicy',
      'impl:$implementationVersion',
    ].join('|');
  }
  return tradingLabLegacyStrategyIdentityKey(idea);
}

String tradingLabLegacyStrategyIdentityKey(TradeIdea idea) =>
    '${idea.strategy.name}@${idea.strategyVersion}';

bool tradingLabManifestAcceptsIdea(
  TradingLabRunManifest manifest,
  TradeIdea idea,
) {
  final exact = tradingLabStrategyIdentityKey(idea);
  if (manifest.strategies.contains(exact)) return true;

  // Historical manifests created before immutable registry attribution stored
  // only the legacy strategy/version pair. Keep them replayable without
  // upgrading their provenance or granting additional execution authority.
  return manifest.strategies.contains(tradingLabLegacyStrategyIdentityKey(idea));
}

bool getTradingLabIdeaHasImmutableRegistryIdentity(TradeIdea idea) =>
    idea.registryStrategyId.trim().isNotEmpty &&
    idea.registryStrategyVersion.trim().isNotEmpty &&
    idea.strategySnapshotHash.trim().isNotEmpty &&
    idea.managementPolicyVersion.trim().isNotEmpty &&
    idea.strategyImplementationVersion.trim().isNotEmpty &&
    idea.strategyParameterSchemaVersion > 0;
