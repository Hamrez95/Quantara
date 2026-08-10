import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_zip_bundle.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_account_context.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  TradingLabRun buildRun() => TradingLabRun(
    manifest: TradingLabRunManifest(
      runId: 'lab-zip-roundtrip',
      startedAtUtc: DateTime.utc(2026, 8, 10, 3),
      startingEquity: 500,
      riskPercent: 1,
      maximumConcurrentPositions: 3,
      leverage: 5,
      symbols: const ['BTCUSDT', 'ETHUSDT'],
      timeframes: const ['15m', '1h'],
      strategies: const ['trendPullback@v1'],
      feeRateBps: 6,
      slippageBps: 2,
      notes: 'portable evidence',
    ),
    balance: 505,
    currentEquity: 508,
    peakEquity: 510,
    maximumDrawdownPercent: 1.2,
    cycleId: 7,
    lastSnapshotAtUtc: DateTime.utc(2026, 8, 10, 4),
    lastWhyNoTrade: 'Scanner active; no candidate met admission.',
    processedDecisionKeys: const ['decision-a'],
  );

  const accountContext = TradingLabAccountContext(
    connected: true,
    reconciliationHealth: 'healthy',
    refreshing: false,
    blocksNewEntries: false,
    canManageExistingPositions: true,
    marginCoin: 'USDT',
    available: 420,
    estimatedEquity: 510,
    openPositionCount: 1,
    pendingOrderCount: 0,
    allOpenPositionsFullyProtected: true,
  );

  test('full Lab evidence is a standard ZIP and round-trips safely', () {
    final run = buildRun();
    final aiReview = jsonEncode({
      'schemaVersion': 1,
      'runId': run.manifest.runId,
      'scorecards': const [],
    });
    final shadow = <String, Object?>{
      'summary': const {'signalsTracked': 3},
      'scorecards': const <Object?>[],
      'signals': const <Object?>[],
    };

    final bundle = const TradingLabZipBundleCodec().encode(
      run: run,
      aiReviewJson: aiReview,
      shadowEvidence: shadow,
      accountContext: accountContext,
    );

    expect(bundle.fileName, 'quantara-lab-lab-zip-roundtrip.zip');
    expect(bundle.bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);

    final restored = const TradingLabZipBundleCodec().decode(bundle.bytes);
    expect(restored.run.manifest.runId, run.manifest.runId);
    expect(restored.run.currentEquity, 508);
    expect(restored.aiReviewJson, contains('lab-zip-roundtrip'));
    expect(restored.shadowEvidenceJson, contains('signalsTracked'));
    expect(restored.accountContextJson, contains('read_only_context'));
  });

  test('ZIP corruption is rejected instead of silently importing evidence', () {
    final run = buildRun();
    final bundle = const TradingLabZipBundleCodec().encode(
      run: run,
      aiReviewJson: jsonEncode({'runId': run.manifest.runId}),
      shadowEvidence: const {'signals': <Object?>[]},
      accountContext: accountContext,
    );
    final corrupted = Uint8List.fromList(bundle.bytes);
    final readme = utf8.encode('Quantara Bot Trading Lab evidence bundle');
    final offset = _indexOf(corrupted, readme);
    expect(offset, greaterThanOrEqualTo(0));
    corrupted[offset] ^= 0x01;

    expect(
      () => const TradingLabZipBundleCodec().decode(corrupted),
      throwsFormatException,
    );
  });

  test('sensitive credential-shaped keys fail closed before export', () {
    final run = buildRun();
    expect(
      () => const TradingLabZipBundleCodec().encode(
        run: run,
        aiReviewJson: jsonEncode({
          'runId': run.manifest.runId,
          'apiSecret': 'must-never-export',
        }),
        shadowEvidence: const {'signals': <Object?>[]},
        accountContext: accountContext,
      ),
      throwsFormatException,
    );
  });
}

int _indexOf(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty) return 0;
  for (var start = 0; start <= haystack.length - needle.length; start += 1) {
    var matches = true;
    for (var index = 0; index < needle.length; index += 1) {
      if (haystack[start + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return -1;
}
