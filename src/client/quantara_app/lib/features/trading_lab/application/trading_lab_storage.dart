import 'dart:convert';
import 'dart:math' as math;

import '../domain/trading_lab_models.dart';

final class TradingLabStorageUsage {
  const TradingLabStorageUsage({
    required this.estimatedBytes,
    required this.reclaimableBytes,
    required this.retainedBytes,
  });

  final int estimatedBytes;
  final int reclaimableBytes;
  final int retainedBytes;

  bool get canReclaim => reclaimableBytes > 0;
}

final class TradingLabStorage {
  const TradingLabStorage._();

  static int estimateBytes(TradingLabRun run) =>
      utf8.encode(jsonEncode(run.toJson())).length;

  static TradingLabStorageUsage usage(TradingLabRun run) {
    final fullBytes = estimateBytes(run);
    if (run.isRunning) {
      return TradingLabStorageUsage(
        estimatedBytes: fullBytes,
        reclaimableBytes: 0,
        retainedBytes: fullBytes,
      );
    }
    final compacted = compactHeavyEvidence(run);
    final retainedBytes = estimateBytes(compacted);
    return TradingLabStorageUsage(
      estimatedBytes: fullBytes,
      reclaimableBytes: math.max(0, fullBytes - retainedBytes),
      retainedBytes: retainedBytes,
    );
  }

  static TradingLabRun compactHeavyEvidence(TradingLabRun run) {
    if (run.isRunning) {
      throw StateError(
        'Stop the Trading Lab evaluation before reclaiming local evidence.',
      );
    }
    return run.copyWith(
      pendingCandidates: const <TradingLabCandidate>[],
      events: const <TradingLabEvent>[],
      processedDecisionKeys: const <String>{},
    );
  }
}
