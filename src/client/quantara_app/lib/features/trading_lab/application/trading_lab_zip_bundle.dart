import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/trading_lab_account_context.dart';
import '../domain/trading_lab_models.dart';

const tradingLabBundleSchemaVersion = 2;
const _maximumBundleBytes = 32 * 1024 * 1024;
const _maximumBundleFiles = 32;

final class TradingLabZipBundle {
  const TradingLabZipBundle({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

final class TradingLabImportedBundle {
  const TradingLabImportedBundle({
    required this.run,
    required this.aiReviewJson,
    required this.shadowEvidenceJson,
    required this.accountContextJson,
    required this.fileNames,
  });

  final TradingLabRun run;
  final String aiReviewJson;
  final String shadowEvidenceJson;
  final String accountContextJson;
  final Set<String> fileNames;
}

final class TradingLabZipBundleCodec {
  const TradingLabZipBundleCodec();

  static const requiredEvidenceFiles = <String>{
    'bundle_manifest.json',
    'manifest.json',
    'summary.json',
    'run.json',
    'trades.jsonl',
    'candidates.jsonl',
    'decisions.jsonl',
    'management_events.jsonl',
    'equity_curve.jsonl',
    'market_feature_snapshots.jsonl',
    'anomalies.jsonl',
    'strategy_versions.json',
    'ai_review.json',
    'shadow_evidence.json',
    'account_context.json',
    'README.txt',
  };

  TradingLabZipBundle encode({
    required TradingLabRun run,
    required String aiReviewJson,
    required Map<String, Object?> shadowEvidence,
    required TradingLabAccountContext accountContext,
  }) {
    final pretty = const JsonEncoder.withIndent('  ');
    final runObject = run.toJson();
    final manifestObject = run.manifest.toJson();
    final accountObject = accountContext.toJson();
    final summaryObject = _summary(run);
    final strategyVersionsObject = <String, Object?>{
      'schemaVersion': tradingLabBundleSchemaVersion,
      'runId': run.manifest.runId,
      'strategies': run.manifest.strategies,
    };

    final trades = <Map<String, Object?>>[
      for (final position in run.closedPositions)
        {'state': 'closed', ...position.toJson()},
      for (final position in run.openPositions)
        {'state': 'open', ...position.toJson()},
    ];
    final candidates = <Map<String, Object?>>[
      for (final candidate in run.pendingCandidates)
        {'state': 'pending', ...candidate.toJson()},
    ];
    final decisions = run.events
        .where(
          (event) =>
              event.kind == TradingLabEventKind.candidateObserved ||
              event.kind == TradingLabEventKind.candidatePending ||
              event.kind == TradingLabEventKind.candidateRejected,
        )
        .map((event) => event.toJson())
        .toList(growable: false);
    final managementEvents = run.events
        .where(
          (event) =>
              event.kind == TradingLabEventKind.positionOpened ||
              event.kind == TradingLabEventKind.targetFilled ||
              event.kind == TradingLabEventKind.stopPromoted ||
              event.kind == TradingLabEventKind.stopFilled ||
              event.kind == TradingLabEventKind.positionClosed,
        )
        .map((event) => event.toJson())
        .toList(growable: false);
    final equityCurve = run.events
        .where((event) => event.kind == TradingLabEventKind.heartbeat)
        .map(
          (event) => <String, Object?>{
            'atUtc': event.atUtc.toIso8601String(),
            'cycleId': event.cycleId,
            'equity': event.metrics['equity'],
            'balance': event.metrics['balance'],
            'openPositions': event.metrics['openPositions'],
            'pendingCandidates': event.metrics['pendingCandidates'],
            'closedTrades': event.metrics['closedTrades'],
            'maximumDrawdownPercent': event.metrics['maximumDrawdownPercent'],
          },
        )
        .toList(growable: false);
    final marketFeatureSnapshots = run.events
        .where((event) => event.kind == TradingLabEventKind.candidateObserved)
        .map(
          (event) => <String, Object?>{
            'atUtc': event.atUtc.toIso8601String(),
            'cycleId': event.cycleId,
            'setupId': event.setupId,
            'symbol': event.symbol,
            'timeframe': event.timeframe,
            'strategy': event.strategy,
            'strategyVersion': event.strategyVersion,
            'features': event.metrics,
            'attributes': event.attributes,
          },
        )
        .toList(growable: false);
    final anomalies = run.events
        .where((event) => event.kind == TradingLabEventKind.anomaly)
        .map((event) => event.toJson())
        .toList(growable: false);

    final objectsToValidate = <Object?>[
      runObject,
      manifestObject,
      summaryObject,
      strategyVersionsObject,
      trades,
      candidates,
      decisions,
      managementEvents,
      equityCurve,
      marketFeatureSnapshots,
      anomalies,
      shadowEvidence,
      accountObject,
      jsonDecode(aiReviewJson),
    ];
    for (final value in objectsToValidate) {
      _assertNoSensitiveKeys(value);
    }

    final payloadFiles = <String, Uint8List>{
      'manifest.json': _utf8(pretty.convert(manifestObject)),
      'summary.json': _utf8(pretty.convert(summaryObject)),
      'run.json': _utf8(pretty.convert(runObject)),
      'trades.jsonl': _utf8(_jsonl(trades)),
      'candidates.jsonl': _utf8(_jsonl(candidates)),
      'decisions.jsonl': _utf8(_jsonl(decisions)),
      'management_events.jsonl': _utf8(_jsonl(managementEvents)),
      'equity_curve.jsonl': _utf8(_jsonl(equityCurve)),
      'market_feature_snapshots.jsonl': _utf8(_jsonl(marketFeatureSnapshots)),
      'anomalies.jsonl': _utf8(_jsonl(anomalies)),
      'strategy_versions.json': _utf8(pretty.convert(strategyVersionsObject)),
      'ai_review.json': _utf8(aiReviewJson),
      'shadow_evidence.json': _utf8(pretty.convert(shadowEvidence)),
      'account_context.json': _utf8(pretty.convert(accountObject)),
      'README.txt': _utf8(_readme(run)),
    };
    final checksums = <String, String>{
      for (final entry in payloadFiles.entries)
        entry.key: sha256.convert(entry.value).toString(),
    };
    final bundleManifest = <String, Object?>{
      'bundleSchemaVersion': tradingLabBundleSchemaVersion,
      'product': 'Quantara',
      'bundleType': 'bot-trading-lab-evidence',
      'runId': run.manifest.runId,
      'runStartedAtUtc': run.manifest.startedAtUtc.toIso8601String(),
      'paperOnly': true,
      'containsCredentials': false,
      'files': payloadFiles.keys.toList(growable: false),
      'checksumsSha256': checksums,
    };
    final files = <String, Uint8List>{
      'bundle_manifest.json': _utf8(pretty.convert(bundleManifest)),
      ...payloadFiles,
    };
    if (!files.keys.toSet().containsAll(requiredEvidenceFiles)) {
      throw const StateError(
        'Trading Lab evidence bundle contract is incomplete.',
      );
    }
    final bytes = _StoredZipCodec.encode(files);
    if (bytes.length > _maximumBundleBytes) {
      throw const FormatException('Trading Lab ZIP bundle exceeds 32 MiB.');
    }
    return TradingLabZipBundle(
      bytes: bytes,
      fileName: 'quantara-lab-${run.manifest.runId}.zip',
    );
  }

  TradingLabImportedBundle decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maximumBundleBytes) {
      throw const FormatException('Trading Lab ZIP bundle size is invalid.');
    }
    final files = _StoredZipCodec.decode(bytes);
    if (files.length > _maximumBundleFiles) {
      throw const FormatException(
        'Trading Lab ZIP bundle contains too many files.',
      );
    }
    if (!files.keys.toSet().containsAll(requiredEvidenceFiles)) {
      throw const FormatException('Trading Lab ZIP bundle is incomplete.');
    }

    final bundleManifest = _jsonObject(files['bundle_manifest.json']!);
    if (_int(bundleManifest['bundleSchemaVersion']) !=
        tradingLabBundleSchemaVersion) {
      throw const FormatException('Unsupported Trading Lab bundle schema.');
    }
    if (bundleManifest['bundleType'] != 'bot-trading-lab-evidence' ||
        bundleManifest['paperOnly'] != true ||
        bundleManifest['containsCredentials'] != false) {
      throw const FormatException(
        'Trading Lab bundle safety metadata is invalid.',
      );
    }

    final declaredFiles =
        (bundleManifest['files'] as List<Object?>? ?? const [])
            .map((item) => item.toString())
            .toSet();
    if (!declaredFiles.containsAll(
      requiredEvidenceFiles.difference({'bundle_manifest.json'}),
    )) {
      throw const FormatException(
        'Trading Lab bundle manifest does not declare all evidence files.',
      );
    }

    final checksumJson = bundleManifest['checksumsSha256'];
    if (checksumJson is! Map) {
      throw const FormatException('Trading Lab bundle checksums are missing.');
    }
    for (final entry in checksumJson.entries) {
      final name = entry.key.toString();
      final expected = entry.value.toString();
      final data = files[name];
      if (data == null || sha256.convert(data).toString() != expected) {
        throw FormatException('Trading Lab bundle checksum failed for $name.');
      }
    }

    final runJson = utf8.decode(files['run.json']!);
    final aiReviewJson = utf8.decode(files['ai_review.json']!);
    final shadowJson = utf8.decode(files['shadow_evidence.json']!);
    final accountJson = utf8.decode(files['account_context.json']!);
    final manifest = _jsonObject(files['manifest.json']!);
    final runMap = jsonDecode(runJson);
    _assertNoSensitiveKeys(runMap);
    _assertNoSensitiveKeys(jsonDecode(aiReviewJson));
    _assertNoSensitiveKeys(jsonDecode(shadowJson));
    _assertNoSensitiveKeys(jsonDecode(accountJson));
    for (final name in const <String>[
      'trades.jsonl',
      'candidates.jsonl',
      'decisions.jsonl',
      'management_events.jsonl',
      'equity_curve.jsonl',
      'market_feature_snapshots.jsonl',
      'anomalies.jsonl',
    ]) {
      _validateJsonl(files[name]!, name);
    }
    if (runMap is! Map) {
      throw const FormatException('Trading Lab run payload is invalid.');
    }
    final run = TradingLabRun.fromJson(
      runMap.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (manifest['runId']?.toString() != run.manifest.runId ||
        bundleManifest['runId']?.toString() != run.manifest.runId) {
      throw const FormatException('Trading Lab bundle run identity mismatch.');
    }
    return TradingLabImportedBundle(
      run: run,
      aiReviewJson: aiReviewJson,
      shadowEvidenceJson: shadowJson,
      accountContextJson: accountJson,
      fileNames: Set.unmodifiable(files.keys.toSet()),
    );
  }

  static Map<String, Object?> _summary(TradingLabRun run) => {
    'schemaVersion': tradingLabBundleSchemaVersion,
    'runId': run.manifest.runId,
    'status': run.status.name,
    'startingEquity': run.manifest.startingEquity,
    'balance': run.balance,
    'currentEquity': run.currentEquity,
    'returnPercent': run.returnPercent,
    'maximumDrawdownPercent': run.maximumDrawdownPercent,
    'openPositions': run.openPositions.length,
    'pendingCandidates': run.pendingCandidates.length,
    'tradeCount': run.tradeCount,
    'wins': run.wins,
    'losses': run.losses,
    'winRatePercent': run.winRatePercent,
    'netRealizedPnl': run.netRealizedPnl,
    'grossProfit': run.grossProfit,
    'grossLoss': run.grossLoss,
    'profitFactor': run.profitFactor?.isFinite == true
        ? run.profitFactor
        : null,
    'averageR': run.averageR,
    'cycleId': run.cycleId,
    'lastSnapshotAtUtc': run.lastSnapshotAtUtc?.toIso8601String(),
    'lastWhyNoTrade': run.lastWhyNoTrade,
  };

  static String _jsonl(Iterable<Map<String, Object?>> rows) =>
      rows.map(jsonEncode).join('\n');

  static Uint8List _utf8(String value) =>
      Uint8List.fromList(utf8.encode(value));

  static Map<String, Object?> _jsonObject(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Trading Lab bundle JSON object expected.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  static void _validateJsonl(Uint8List bytes, String name) {
    final text = utf8.decode(bytes);
    if (text.trim().isEmpty) return;
    var lineNumber = 0;
    for (final line in const LineSplitter().convert(text)) {
      lineNumber += 1;
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw FormatException('$name line $lineNumber must be a JSON object.');
      }
      _assertNoSensitiveKeys(decoded, '$name:$lineNumber');
    }
  }

  static int _int(Object? value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text) ?? -1,
    _ => -1,
  };

  static void _assertNoSensitiveKeys(Object? value, [String path = r'$']) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalized = key.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        const forbidden = <String>{
          'apikey',
          'apisecret',
          'secretkey',
          'credential',
          'credentials',
          'authorization',
          'password',
          'privatekey',
          'accesstoken',
          'refreshtoken',
        };
        if (forbidden.contains(normalized)) {
          throw FormatException(
            'Sensitive field is not allowed in Lab export: $path.$key',
          );
        }
        _assertNoSensitiveKeys(entry.value, '$path.$key');
      }
      return;
    }
    if (value is Iterable) {
      var index = 0;
      for (final item in value) {
        _assertNoSensitiveKeys(item, '$path[$index]');
        index += 1;
      }
    }
  }

  static String _readme(TradingLabRun run) =>
      '''Quantara Bot Trading Lab evidence bundle

Run: ${run.manifest.runId}
Started (UTC): ${run.manifest.startedAtUtc.toIso8601String()}
Mode: PAPER / FORWARD TEST ONLY
Bundle schema: $tradingLabBundleSchemaVersion

Files:
- bundle_manifest.json: bundle identity, safety flags and SHA-256 checksums
- manifest.json: immutable experiment configuration and strategy versions
- summary.json: normalized run scorecard
- run.json: complete durable paper-run state
- trades.jsonl: open and closed paper positions
- candidates.jsonl: currently pending candidates
- decisions.jsonl: observed/pending/rejected candidate decisions
- management_events.jsonl: paper entry, TP, stop promotion, stop and close events
- equity_curve.jsonl: heartbeat-derived equity/balance/drawdown series
- market_feature_snapshots.jsonl: bounded candidate feature/indicator evidence
- anomalies.jsonl: explicit Lab anomaly events
- strategy_versions.json: strategy/version identities used by the run
- ai_review.json: deterministic AI review payload and scorecards
- shadow_evidence.json: tracked outcomes for Quantara signals, including non-entered setups
- account_context.json: sanitized read-only account health/equity context
- README.txt: this schema guide

No API key, API secret, authorization header, password or private key is intentionally included.
The Trading Lab does not have a real-order execution path.
Imported bundles are restored stopped/read-only and never resume live processing automatically.
''';
}

final class _StoredZipCodec {
  const _StoredZipCodec._();

  static Uint8List encode(Map<String, Uint8List> files) {
    if (files.isEmpty || files.length > _maximumBundleFiles) {
      throw const FormatException('Invalid Trading Lab ZIP file count.');
    }
    final output = BytesBuilder(copy: false);
    final central = <_CentralRecord>[];
    var offset = 0;
    for (final entry in files.entries) {
      _validateName(entry.key);
      final nameBytes = Uint8List.fromList(utf8.encode(entry.key));
      final data = entry.value;
      final crc = _crc32(data);
      final local = BytesBuilder(copy: false)
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(nameBytes)
        ..add(data);
      final localBytes = local.takeBytes();
      output.add(localBytes);
      central.add(
        _CentralRecord(
          nameBytes: nameBytes,
          crc32: crc,
          size: data.length,
          localOffset: offset,
        ),
      );
      offset += localBytes.length;
    }

    final centralOffset = offset;
    final centralBuilder = BytesBuilder(copy: false);
    for (final record in central) {
      centralBuilder
        ..add(_u32(0x02014b50))
        ..add(_u16(20))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(record.crc32))
        ..add(_u32(record.size))
        ..add(_u32(record.size))
        ..add(_u16(record.nameBytes.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(record.localOffset))
        ..add(record.nameBytes);
    }
    final centralBytes = centralBuilder.takeBytes();
    output
      ..add(centralBytes)
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(central.length))
      ..add(_u16(central.length))
      ..add(_u32(centralBytes.length))
      ..add(_u32(centralOffset))
      ..add(_u16(0));
    return output.takeBytes();
  }

  static Map<String, Uint8List> decode(Uint8List bytes) {
    final eocd = _findEocd(bytes);
    final count = _readU16(bytes, eocd + 10);
    final centralSize = _readU32(bytes, eocd + 12);
    final centralOffset = _readU32(bytes, eocd + 16);
    if (count < 1 ||
        count > _maximumBundleFiles ||
        centralOffset + centralSize > eocd) {
      throw const FormatException('Invalid Trading Lab ZIP central directory.');
    }
    var cursor = centralOffset;
    final result = <String, Uint8List>{};
    for (var index = 0; index < count; index += 1) {
      if (_readU32(bytes, cursor) != 0x02014b50) {
        throw const FormatException('Invalid Trading Lab ZIP central entry.');
      }
      final flags = _readU16(bytes, cursor + 8);
      final compression = _readU16(bytes, cursor + 10);
      final crc = _readU32(bytes, cursor + 16);
      final compressedSize = _readU32(bytes, cursor + 20);
      final uncompressedSize = _readU32(bytes, cursor + 24);
      final nameLength = _readU16(bytes, cursor + 28);
      final extraLength = _readU16(bytes, cursor + 30);
      final commentLength = _readU16(bytes, cursor + 32);
      final localOffset = _readU32(bytes, cursor + 42);
      if ((flags & 0x0001) != 0 ||
          compression != 0 ||
          compressedSize != uncompressedSize) {
        throw const FormatException(
          'Only unencrypted stored ZIP entries are supported.',
        );
      }
      final nameStart = cursor + 46;
      final nameEnd = nameStart + nameLength;
      _bounds(bytes, nameStart, nameLength);
      final name = utf8.decode(bytes.sublist(nameStart, nameEnd));
      _validateName(name);
      if (result.containsKey(name)) {
        throw FormatException('Duplicate Trading Lab ZIP entry: $name');
      }

      if (_readU32(bytes, localOffset) != 0x04034b50) {
        throw const FormatException('Invalid Trading Lab ZIP local entry.');
      }
      final localNameLength = _readU16(bytes, localOffset + 26);
      final localExtraLength = _readU16(bytes, localOffset + 28);
      final dataStart = localOffset + 30 + localNameLength + localExtraLength;
      _bounds(bytes, dataStart, uncompressedSize);
      final data = Uint8List.fromList(
        bytes.sublist(dataStart, dataStart + uncompressedSize),
      );
      if (_crc32(data) != crc) {
        throw FormatException(
          'CRC32 mismatch for Trading Lab ZIP entry: $name',
        );
      }
      result[name] = data;
      cursor = nameEnd + extraLength + commentLength;
    }
    return Map.unmodifiable(result);
  }

  static int _findEocd(Uint8List bytes) {
    if (bytes.length < 22) {
      throw const FormatException('Trading Lab ZIP is truncated.');
    }
    final start = bytes.length - 22;
    final minimum = bytes.length > 65557 ? bytes.length - 65557 : 0;
    for (var offset = start; offset >= minimum; offset -= 1) {
      if (_readU32(bytes, offset) == 0x06054b50) return offset;
    }
    throw const FormatException('Trading Lab ZIP end record is missing.');
  }

  static void _validateName(String name) {
    if (name.isEmpty ||
        name.length > 120 ||
        name.startsWith('/') ||
        name.startsWith(r'\') ||
        name.contains('..') ||
        name.contains(r'\') ||
        name.contains(':')) {
      throw FormatException('Unsafe Trading Lab ZIP entry name: $name');
    }
  }

  static void _bounds(Uint8List bytes, int start, int length) {
    if (start < 0 || length < 0 || start + length > bytes.length) {
      throw const FormatException('Trading Lab ZIP entry is out of bounds.');
    }
  }

  static Uint8List _u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static int _readU16(Uint8List bytes, int offset) {
    _bounds(bytes, offset, 2);
    return ByteData.sublistView(
      bytes,
      offset,
      offset + 2,
    ).getUint16(0, Endian.little);
  }

  static int _readU32(Uint8List bytes, int offset) {
    _bounds(bytes, offset, 4);
    return ByteData.sublistView(
      bytes,
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit += 1) {
        crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}

final class _CentralRecord {
  const _CentralRecord({
    required this.nameBytes,
    required this.crc32,
    required this.size,
    required this.localOffset,
  });

  final Uint8List nameBytes;
  final int crc32;
  final int size;
  final int localOffset;
}
