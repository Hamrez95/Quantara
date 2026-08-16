from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'missing patch target in {path}: {old[:140]!r}')
    path.write_text(text.replace(old, new, 1))


# Tighten the classifier vocabulary: a position is recoverable only after the
# stronger q-local/history/protection recovery policy has verified ownership.
classifier = ROOT / 'lib/features/auto_trade/domain/exchange_position_ownership.dart'
text = classifier.read_text()
text = text.replace(
    'exchangeHistoryNotVerifiedClear,',
    'quantaraOwnershipNotVerified,',
)
text = text.replace(
    'Iterable<String> historyVerifiedClearPositionIds = const [],',
    'Iterable<String> verifiedQuantaraRecoveryPositionIds = const [],',
)
text = text.replace(
    'final historyClear = historyVerifiedClearPositionIds',
    'final verifiedRecovery = verifiedQuantaraRecoveryPositionIds',
)
text = text.replace(
    'if (!historyClear.contains(id)) {\n        blocks.add(\n          ExchangePositionRecoveryBlock.exchangeHistoryNotVerifiedClear,\n        );\n      }',
    'if (!verifiedRecovery.contains(id)) {\n        blocks.add(\n          ExchangePositionRecoveryBlock.quantaraOwnershipNotVerified,\n        );\n      }',
)
classifier.write_text(text)

classifier_test = ROOT / 'test/exchange_position_ownership_test.dart'
text = classifier_test.read_text()
text = text.replace(
    'historyVerifiedClearPositionIds',
    'verifiedQuantaraRecoveryPositionIds',
)
text = text.replace(
    'ExchangePositionRecoveryBlock.exchangeHistoryNotVerifiedClear',
    'ExchangePositionRecoveryBlock.quantaraOwnershipNotVerified',
)
text = text.replace(
    "'fully protected orphan is not recoverable until history is verified clear'",
    "'fully protected orphan is not recoverable until Quantara ownership is verified'",
)
text = text.replace(
    "'history-clear isolated fully protected orphan becomes recoverable only'",
    "'verified Quantara isolated fully protected orphan becomes recoverable only'",
)
classifier_test.write_text(text)

# Transaction test fixtures now carry the durable managed reconstruction plan.
transaction_test = ROOT / 'test/exchange_position_recovery_transaction_test.dart'
text = transaction_test.read_text()
text = text.replace(
    "    updatedAtUtc: first,\n  );",
    "    updatedAtUtc: first,\n    managedPlan: const {'positionId': 'p-1', 'symbol': 'XRPUSDT'},\n  );",
    1,
)
transaction_test.write_text(text)

# Expand status serialization without breaking old readers/writers.
models = ROOT / 'lib/features/auto_trade/domain/local_live_trade_models.dart'
replace_once(
    models,
    '    this.unmanagedPositionCount = 0,\n    this.unmanagedSymbols = const [],\n    this.entryBlockReason,\n',
    '''    this.unmanagedPositionCount = 0,\n    this.unmanagedSymbols = const [],\n    this.recoverableOrphanCount = 0,\n    this.recoverableOrphanSymbols = const [],\n    this.externalUnmanagedPositionCount = 0,\n    this.externalUnmanagedSymbols = const [],\n    this.recoveryPendingStages = const {},\n    this.entryBlockReason,\n''',
)
replace_once(
    models,
    '  final int unmanagedPositionCount;\n  final List<String> unmanagedSymbols;\n  final String? entryBlockReason;\n',
    '''  final int unmanagedPositionCount;\n  final List<String> unmanagedSymbols;\n\n  /// Exchange positions proven to be Quantara-owned but not yet durably\n  /// committed across Journal, risk ledger and local managed state.\n  final int recoverableOrphanCount;\n  final List<String> recoverableOrphanSymbols;\n\n  /// Open positions whose Quantara ownership cannot be proven. They consume\n  /// slots and block entry, but are never auto-adopted.\n  final int externalUnmanagedPositionCount;\n  final List<String> externalUnmanagedSymbols;\n  final Map<String, String> recoveryPendingStages;\n  final String? entryBlockReason;\n''',
)
replace_once(
    models,
    "    'unmanagedPositionCount': unmanagedPositionCount,\n    'unmanagedSymbols': unmanagedSymbols,\n    'entryBlockReason': entryBlockReason,\n",
    '''    'unmanagedPositionCount': unmanagedPositionCount,\n    'unmanagedSymbols': unmanagedSymbols,\n    'recoverableOrphanCount': recoverableOrphanCount,\n    'recoverableOrphanSymbols': recoverableOrphanSymbols,\n    'externalUnmanagedPositionCount': externalUnmanagedPositionCount,\n    'externalUnmanagedSymbols': externalUnmanagedSymbols,\n    'recoveryPendingStages': recoveryPendingStages,\n    'entryBlockReason': entryBlockReason,\n''',
)
replace_once(
    models,
    "    unmanagedSymbols: List.unmodifiable(\n      (json['unmanagedSymbols'] as List<Object?>? ?? const [])\n          .map((item) => item.toString())\n          .where((item) => item.trim().isNotEmpty),\n    ),\n    entryBlockReason: json['entryBlockReason']?.toString(),\n",
    '''    unmanagedSymbols: List.unmodifiable(\n      (json['unmanagedSymbols'] as List<Object?>? ?? const [])\n          .map((item) => item.toString())\n          .where((item) => item.trim().isNotEmpty),\n    ),\n    recoverableOrphanCount:\n        (json['recoverableOrphanCount'] as num?)?.toInt() ?? 0,\n    recoverableOrphanSymbols: List.unmodifiable(\n      (json['recoverableOrphanSymbols'] as List<Object?>? ?? const [])\n          .map((item) => item.toString())\n          .where((item) => item.trim().isNotEmpty),\n    ),\n    externalUnmanagedPositionCount:\n        (json['externalUnmanagedPositionCount'] as num?)?.toInt() ??\n        (((json['unmanagedPositionCount'] as num?)?.toInt() ?? 0) -\n                ((json['recoverableOrphanCount'] as num?)?.toInt() ?? 0))\n            .clamp(0, 1 << 31),\n    externalUnmanagedSymbols: List.unmodifiable(\n      (json['externalUnmanagedSymbols'] as List<Object?>? ?? const [])\n          .map((item) => item.toString())\n          .where((item) => item.trim().isNotEmpty),\n    ),\n    recoveryPendingStages: _stringStringMap(json['recoveryPendingStages']),\n    entryBlockReason: json['entryBlockReason']?.toString(),\n''',
)
models_text = models.read_text()
helper_marker = 'Map<String, Object?>? _stringObjectMap(Object? value) {\n'
if '_stringStringMap(Object? value)' not in models_text:
    helper = '''Map<String, String> _stringStringMap(Object? value) {\n  if (value is! Map<Object?, Object?>) return const {};\n  return Map.unmodifiable(\n    value.map((key, item) => MapEntry(key.toString(), item.toString())),\n  );\n}\n\n'''
    if helper_marker not in models_text:
        raise SystemExit('status helper marker missing')
    models.write_text(models_text.replace(helper_marker, helper + helper_marker, 1))

# Wire durable checkpoints + three-state ownership into the foreground worker.
service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
replace_once(
    service,
    "import '../domain/auto_trade_models.dart';\n",
    "import '../domain/auto_trade_models.dart';\nimport '../domain/exchange_position_ownership.dart';\n",
)
replace_once(
    service,
    "import 'local_live_canonical_decision.dart';\n",
    "import 'exchange_position_recovery_transaction.dart';\nimport 'local_live_canonical_decision.dart';\n",
)
replace_once(
    service,
    "const localLiveManagementOnlyAfterFlatKey =\n    'quantara.local-live.management-only-after-flat.v1';\n",
    "const localLiveManagementOnlyAfterFlatKey =\n    'quantara.local-live.management-only-after-flat.v1';\nconst localLiveRecoveryCheckpointsKey =\n    'quantara.local-live.recovery-checkpoints.v1';\n",
)
replace_once(
    service,
    '  List<String> _unmanagedSymbols = const [];\n  String? _entryBlockReason;\n',
    '''  List<String> _unmanagedSymbols = const [];\n  List<String> _recoverableOrphanSymbols = const [];\n  List<String> _externalUnmanagedSymbols = const [];\n  final Map<String, ExchangePositionRecoveryCheckpoint>\n  _recoveryCheckpoints = {};\n  final Set<String> _verifiedRecoverablePositionIds = {};\n  String? _entryBlockReason;\n''',
)

cycle_start = '      await _recoverVerifiedQuantaraOrphans(account, openExchangePositions);\n'
cycle_end = '      final hasUnmanagedExchangeExposure = unmanagedPositions.isNotEmpty;\n'
service_text = service.read_text()
start = service_text.find(cycle_start)
end = service_text.find(cycle_end, start)
if start < 0 or end < 0:
    raise SystemExit('cycle ownership block markers missing')
end += len(cycle_end)
cycle_replacement = r'''      _verifiedRecoverablePositionIds.clear();
      await _recoverVerifiedQuantaraOrphans(account, openExchangePositions);
      final sessionId = _sessionId;
      final sessionStartedAt = _sessionStartedAt;
      _sessionPnlProjection = sessionId == null || sessionStartedAt == null
          ? account.authoritativePnl
          : account.authoritativePnl.forSession(
              sessionId: sessionId,
              startedAt: sessionStartedAt,
              ownedPositionIds: Set.unmodifiable(_sessionPositionIds),
            );
      await _reconcilePendingJournalClosures(account.authoritativePnl);
      final ownership = ExchangePositionOwnershipClassifier.classify(
        account: account,
        managedPositions: _managed,
        verifiedQuantaraRecoveryPositionIds: _verifiedRecoverablePositionIds,
      );
      final recoverable = ownership.positions
          .where(
            (item) =>
                item.kind == ExchangePositionOwnershipKind.recoverableOrphan,
          )
          .toList(growable: false);
      final external = ownership.positions
          .where(
            (item) =>
                item.kind == ExchangePositionOwnershipKind.externalUnmanaged,
          )
          .toList(growable: false);
      List<String> symbolsOf(
        Iterable<ExchangePositionOwnershipAssessment> assessments,
      ) => (assessments
            .map((item) => item.position.symbol.trim().toUpperCase())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort());
      _recoverableOrphanSymbols = List.unmodifiable(symbolsOf(recoverable));
      _externalUnmanagedSymbols = List.unmodifiable(symbolsOf(external));
      _unmanagedSymbols = List.unmodifiable(
        ({..._recoverableOrphanSymbols, ..._externalUnmanagedSymbols}.toList()
          ..sort()),
      );
      final hasUnmanagedExchangeExposure = ownership.blocksNewEntries;
'''
service.write_text(service_text[:start] + cycle_replacement + service_text[end:])

service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
service_text = service.read_text()
recovery_start = service_text.find(
    '  Future<void> _recoverVerifiedQuantaraOrphans(\n'
)
recovery_end = service_text.find(
    '  Future<void> _reconcilePendingJournalClosures(\n',
    recovery_start,
)
if recovery_start < 0 or recovery_end < 0:
    raise SystemExit('recovery function markers missing')
recovery_code = r'''  Future<void> _recoverVerifiedQuantaraOrphans(
    AutoTradeAccountSnapshot account,
    List<BitunixLivePosition> openPositions,
  ) async {
    final guard = _portfolioGuard;
    final exchange = _exchange;
    final credentials = _credentials;
    if (guard == null || exchange == null || credentials == null) return;

    final openIds = openPositions
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    await _resumeDurableRecoveryCheckpoints(openIds);
    final ownedIds = _managed
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();

    for (final position in openPositions) {
      final positionId = position.positionId.trim();
      if (positionId.isEmpty || ownedIds.contains(positionId)) continue;
      final positionPnl = account.authoritativePnl.forPositionId(positionId);
      final entryOrderId = LocalLiveOrphanRecoveryPolicy.uniqueEntryOrderId(
        position: position,
        pnl: positionPnl,
      );
      if (entryOrderId == null) {
        _auditEvent(
          'orphan_recovery_deferred',
          'A unique explicit entry order was not available for secure ownership recovery.',
          symbol: position.symbol,
        );
        continue;
      }
      try {
        final entryOrder = await exchange.fetchOrderDetail(
          orderId: entryOrderId,
          credentials: credentials,
        );
        final rules = await exchange.fetchInstrumentRules(position.symbol);
        final protection = await exchange.fetchPendingProtection(
          credentials,
          symbol: position.symbol,
          positionId: positionId,
        );
        final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
          position: position,
          pnl: positionPnl,
          protection: protection,
          entryOrder: entryOrder,
          rules: rules,
        );
        final managed = decision.managed;
        if (!decision.allowed || managed == null) {
          _auditEvent(
            'orphan_recovery_blocked',
            decision.reason,
            symbol: position.symbol,
          );
          continue;
        }

        _verifiedRecoverablePositionIds.add(positionId);
        var checkpoint = _recoveryCheckpoints[positionId];
        if (checkpoint == null ||
            checkpoint.symbol != managed.symbol.trim().toUpperCase()) {
          checkpoint = ExchangePositionRecoveryCheckpoint(
            positionId: positionId,
            symbol: managed.symbol.trim().toUpperCase(),
            stage: ExchangePositionRecoveryStage.verified,
            updatedAtUtc: DateTime.now().toUtc(),
            managedPlan: Map.unmodifiable(managed.toJson()),
            reason: 'Current exchange truth proves Quantara ownership.',
          );
          await _setRecoveryCheckpoint(positionId, checkpoint);
        }

        final result = await ExchangePositionRecoveryTransaction.resume(
          checkpoint: checkpoint,
          clock: () => DateTime.now().toUtc(),
          commitJournal: () => _journalObserver.recordRecoveredPosition(
            managed: managed!,
            account: account,
          ),
          adoptRisk: () => guard.adoptVerifiedOpenPosition(
            managed: managed!,
            confirmedStop: managed.originalStopLoss,
            now: DateTime.now().toUtc(),
          ),
          commitManaged: () async {
            if (!_managed.any((item) => item.positionId == positionId)) {
              _managed.add(managed!);
            }
            ownedIds.add(positionId);
            _sessionPositionIds.add(positionId);
            _executedSetupIds.add(managed.setupId);
            await _persistState();
            await _persistSessionMetadata();
          },
          persistCheckpoint: (value) =>
              _setRecoveryCheckpoint(positionId, value),
        );
        if (result.completed) {
          _auditEvent(
            'orphan_recovery_completed',
            'A fully protected Quantara position was recovered from verified exchange truth after reinstall.',
            symbol: position.symbol,
          );
        } else {
          _entriesEnabled = false;
          _entryBlockReason = 'orphanRecoveryPending';
          _auditEvent(
            'orphan_recovery_deferred',
            'Verified Quantara recovery is durable at ${result.checkpoint?.stage.name ?? 'verified'}; ${result.reason}.',
            symbol: position.symbol,
          );
        }
      } on LocalLiveTradeSafeException catch (error) {
        _entriesEnabled = false;
        _entryBlockReason = 'orphanRecoveryPending';
        _auditEvent(
          'orphan_recovery_blocked',
          error.message,
          symbol: position.symbol,
        );
      } on FormatException catch (error) {
        _entriesEnabled = false;
        _entryBlockReason = 'orphanRecoveryPending';
        _auditEvent(
          'orphan_recovery_blocked',
          error.message.toString(),
          symbol: position.symbol,
        );
      } on Object catch (error) {
        _entriesEnabled = false;
        _entryBlockReason = 'orphanRecoveryPending';
        _auditEvent(
          'orphan_recovery_deferred',
          'Durable recovery will retry safely (${_safeError(error)}).',
          symbol: position.symbol,
        );
      }
    }
  }

  Future<void> _resumeDurableRecoveryCheckpoints(Set<String> openIds) async {
    for (final entry in List<MapEntry<String, ExchangePositionRecoveryCheckpoint>>.of(
      _recoveryCheckpoints.entries,
    )) {
      final positionId = entry.key;
      final checkpoint = entry.value;
      if (checkpoint.stage == ExchangePositionRecoveryStage.riskAdopted) {
        try {
          final managed = LocalLiveManagedPosition.fromJson(
            checkpoint.managedPlan,
          );
          if (managed.positionId.trim() != positionId ||
              managed.symbol.trim().toUpperCase() != checkpoint.symbol) {
            throw const FormatException(
              'Recovery checkpoint managed plan does not match exchange identity.',
            );
          }
          if (!_managed.any((item) => item.positionId == positionId)) {
            _managed.add(managed);
          }
          _sessionPositionIds.add(positionId);
          _executedSetupIds.add(managed.setupId);
          await _persistState();
          await _persistSessionMetadata();
          await _setRecoveryCheckpoint(positionId, null);
          _auditEvent(
            'orphan_recovery_resumed',
            'Risk adoption was already durable; managed state was resumed after restart.',
            symbol: checkpoint.symbol,
          );
        } on Object catch (error) {
          _entriesEnabled = false;
          _entryBlockReason = 'orphanRecoveryPending';
          _auditEvent(
            'orphan_recovery_deferred',
            'Risk-adopted recovery checkpoint could not finalize (${_safeError(error)}).',
            symbol: checkpoint.symbol,
          );
        }
        continue;
      }

      if (openIds.contains(positionId)) continue;
      if (checkpoint.stage == ExchangePositionRecoveryStage.journalCommitted) {
        try {
          final managed = LocalLiveManagedPosition.fromJson(
            checkpoint.managedPlan,
          );
          if (!_pendingJournalClosures.any(
            (item) => item.positionId == positionId,
          )) {
            _pendingJournalClosures.add(managed);
          }
          await _persistState();
          await _setRecoveryCheckpoint(positionId, null);
          _auditEvent(
            'orphan_recovery_closed_before_risk',
            'Recovered journal plan is queued for closed-position reconciliation; no open risk was adopted.',
            symbol: checkpoint.symbol,
          );
        } on Object catch (error) {
          _auditEvent(
            'orphan_recovery_deferred',
            'Closed recovery checkpoint remains pending (${_safeError(error)}).',
            symbol: checkpoint.symbol,
          );
        }
      } else {
        await _setRecoveryCheckpoint(positionId, null);
      }
    }
  }

  Future<void> _setRecoveryCheckpoint(
    String positionId,
    ExchangePositionRecoveryCheckpoint? checkpoint,
  ) async {
    if (checkpoint == null) {
      _recoveryCheckpoints.remove(positionId);
    } else {
      _recoveryCheckpoints[positionId] = checkpoint;
    }
    await _persistRecoveryCheckpoints();
  }

  Future<void> _persistRecoveryCheckpoints() => FlutterForegroundTask.saveData(
    key: localLiveRecoveryCheckpointsKey,
    value: jsonEncode(
      _recoveryCheckpoints.values.map((item) => item.toJson()).toList(),
    ),
  );

'''
service.write_text(service_text[:recovery_start] + recovery_code + service_text[recovery_end:])

service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
replace_once(
    service,
    '    final managedRaw = await FlutterForegroundTask.getData<String>(\n      key: localLiveManagedPositionsKey,\n    );\n',
    '''    final recoveryRaw = await FlutterForegroundTask.getData<String>(\n      key: localLiveRecoveryCheckpointsKey,\n    );\n    if (recoveryRaw != null) {\n      try {\n        final decoded = jsonDecode(recoveryRaw);\n        if (decoded is List<Object?>) {\n          _recoveryCheckpoints.clear();\n          for (final raw in decoded.whereType<Map<Object?, Object?>>()) {\n            final checkpoint = ExchangePositionRecoveryCheckpoint.fromJson(\n              raw.map((key, value) => MapEntry(key.toString(), value)),\n            );\n            _recoveryCheckpoints[checkpoint.positionId] = checkpoint;\n          }\n        }\n      } on Object {\n        _recoveryCheckpoints.clear();\n      }\n    }\n    final managedRaw = await FlutterForegroundTask.getData<String>(\n      key: localLiveManagedPositionsKey,\n    );\n''',
)
replace_once(
    service,
    '      unmanagedPositionCount: _unmanagedSymbols.length,\n      unmanagedSymbols: _unmanagedSymbols,\n      entryBlockReason: _entryBlockReason,\n',
    '''      unmanagedPositionCount: _unmanagedSymbols.length,\n      unmanagedSymbols: _unmanagedSymbols,\n      recoverableOrphanCount: _recoverableOrphanSymbols.length,\n      recoverableOrphanSymbols: _recoverableOrphanSymbols,\n      externalUnmanagedPositionCount: _externalUnmanagedSymbols.length,\n      externalUnmanagedSymbols: _externalUnmanagedSymbols,\n      recoveryPendingStages: {\n        for (final entry in _recoveryCheckpoints.entries)\n          if (_verifiedRecoverablePositionIds.contains(entry.key))\n            entry.value.symbol: entry.value.stage.name,\n      },\n      entryBlockReason: _entryBlockReason,\n''',
)

# UI: distinguish proven Quantara recovery from manual/ambiguous exposure.
ui = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
replace_once(
    ui,
    '''    final unrecoveredSymbols = status.unmanagedSymbols.isNotEmpty\n        ? status.unmanagedSymbols\n        : exchangeOpenPositions\n              .map((position) => position.symbol.trim().toUpperCase())\n              .where((symbol) => symbol.isNotEmpty)\n              .toSet()\n              .toList(growable: false);\n''',
    '''    final unrecoveredSymbols = status.unmanagedSymbols.isNotEmpty\n        ? status.unmanagedSymbols\n        : exchangeOpenPositions\n              .map((position) => position.symbol.trim().toUpperCase())\n              .where((symbol) => symbol.isNotEmpty)\n              .toSet()\n              .toList(growable: false);\n    final recoverableCount = math.min(\n      unrecoveredCount,\n      status.recoverableOrphanCount,\n    );\n    final recoverableSymbols = status.recoverableOrphanSymbols;\n    final externalCount = math.max(\n      status.externalUnmanagedPositionCount,\n      unrecoveredCount - recoverableCount,\n    );\n    final externalSymbols = status.externalUnmanagedSymbols.isNotEmpty\n        ? status.externalUnmanagedSymbols\n        : unrecoveredSymbols\n              .where((symbol) => !recoverableSymbols.contains(symbol))\n              .toList(growable: false);\n''',
)
old_notice = '''          if (unrecoveredCount > 0) ...[\n            const SizedBox(height: 10),\n            _BoundaryNotice(\n              text: _t(\n                'Bitunix تعداد $authoritativeOpenCount پوزیشن باز گزارش می‌کند، اما مالکیت محلی $unrecoveredCount پوزیشن (${unrecoveredSymbols.join(', ')}) بعد از حذف برنامه از بین رفته است. این پوزیشن‌ها اسلات و بودجه را اشغال می‌کنند؛ ورود جدید تا بازیابی امن یا بسته‌شدن در صرافی مسدود می‌ماند.',\n                'Bitunix reports $authoritativeOpenCount open position(s), but local ownership for $unrecoveredCount (${unrecoveredSymbols.join(', ')}) was lost after reinstall. These positions consume slots and budget; new entries stay blocked until secure recovery or exchange closure.',\n              ),\n              color: QuantaraColors.warning,\n            ),\n          ],\n'''
new_notice = '''          if (recoverableCount > 0) ...[\n            const SizedBox(height: 10),\n            _BoundaryNotice(\n              text: _t(\n                'مالکیت Quantara برای $recoverableCount پوزیشن (${recoverableSymbols.join(', ')}) از روی سفارش q-local، تاریخچه Fill و حفاظت صرافی تأیید شده است. بازیابی durable در حال تکمیل است و تا پایان Journal + Risk Ledger + Managed State ورود جدید بسته می‌ماند.',\n                'Quantara ownership is verified for $recoverableCount position(s) (${recoverableSymbols.join(', ')}) from q-local order identity, fill history, and exchange protection. Durable recovery is finishing; new entries stay blocked until Journal + Risk Ledger + Managed State all commit.',\n              ),\n              color: QuantaraColors.warning,\n            ),\n          ],\n          if (externalCount > 0) ...[\n            const SizedBox(height: 10),\n            _BoundaryNotice(\n              text: _t(\n                '$externalCount پوزیشن صرافی (${externalSymbols.join(', ')}) مالکیت Quantara قابل‌اثبات ندارد یا حقیقت آن مبهم است. این پوزیشن‌ها اسلات و بودجه را اشغال می‌کنند و خودکار Adopt نمی‌شوند؛ ورود جدید تا بسته‌شدن یا اثبات امن مالکیت مسدود است.',\n                '$externalCount exchange position(s) (${externalSymbols.join(', ')}) do not have provable Quantara ownership or remain ambiguous. They consume slots and budget and are never auto-adopted; new entries stay blocked until closure or safe ownership proof.',\n              ),\n              color: QuantaraColors.danger,\n            ),\n          ],\n'''
replace_once(ui, old_notice, new_notice)
old_pill = '''              if (unrecoveredCount > 0)\n                StatusPill(\n                  label: _t(\n                    '$unrecoveredCount نیازمند بازیابی امن',\n                    '$unrecoveredCount secure recovery pending',\n                  ),\n                  color: QuantaraColors.warning,\n                  icon: Icons.sync_lock_rounded,\n                ),\n'''
new_pill = '''              if (recoverableCount > 0)\n                StatusPill(\n                  label: _t(\n                    '$recoverableCount بازیابی Quantara در انتظار',\n                    '$recoverableCount Quantara recovery pending',\n                  ),\n                  color: QuantaraColors.warning,\n                  icon: Icons.sync_lock_rounded,\n                ),\n              if (externalCount > 0)\n                StatusPill(\n                  label: _t(\n                    '$externalCount پوزیشن خارجی/مبهم',\n                    '$externalCount external/ambiguous',\n                  ),\n                  color: QuantaraColors.danger,\n                  icon: Icons.block_rounded,\n                ),\n'''
replace_once(ui, old_pill, new_pill)

# Add status round-trip coverage for the three ownership states.
status_test = ROOT / 'test/local_live_recovery_status_test.dart'
status_test.write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  test('Local Live status preserves recoverable and external ownership states', () {
    final now = DateTime.utc(2026, 8, 16, 12);
    final status = LocalLiveTradeStatus(
      state: LocalLiveTradeState.managingOnly,
      updatedAt: now,
      message: 'recovery',
      openPositionCount: 2,
      managedPositionCount: 0,
      unmanagedPositionCount: 2,
      unmanagedSymbols: const ['XRPUSDT', 'ETHUSDT'],
      recoverableOrphanCount: 1,
      recoverableOrphanSymbols: const ['XRPUSDT'],
      externalUnmanagedPositionCount: 1,
      externalUnmanagedSymbols: const ['ETHUSDT'],
      recoveryPendingStages: const {
        'XRPUSDT': 'journalCommitted',
      },
      entryBlockReason: 'unmanagedExchangeExposure',
    );

    final restored = LocalLiveTradeStatus.fromJson(status.toJson());
    expect(restored.openPositionCount, 2);
    expect(restored.unmanagedPositionCount, 2);
    expect(restored.recoverableOrphanCount, 1);
    expect(restored.recoverableOrphanSymbols, ['XRPUSDT']);
    expect(restored.externalUnmanagedPositionCount, 1);
    expect(restored.externalUnmanagedSymbols, ['ETHUSDT']);
    expect(restored.recoveryPendingStages['XRPUSDT'], 'journalCommitted');
    expect(restored.requiresExchangeRecovery, isTrue);
    expect(restored.canResumeEntries, isFalse);
  });

  test('old status JSON remains backwards compatible', () {
    final restored = LocalLiveTradeStatus.fromJson({
      'state': 'managingOnly',
      'updatedAt': DateTime.utc(2026, 8, 16).toIso8601String(),
      'message': 'legacy',
      'openPositionCount': 1,
      'managedPositionCount': 0,
      'unmanagedPositionCount': 1,
      'unmanagedSymbols': ['BTCUSDT'],
      'entriesEnabled': false,
    });

    expect(restored.recoverableOrphanCount, 0);
    expect(restored.externalUnmanagedPositionCount, 1);
    expect(restored.recoveryPendingStages, isEmpty);
  });
}
''')
