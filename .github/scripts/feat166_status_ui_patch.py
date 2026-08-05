from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text or text.count(old) != 1:
        raise SystemExit(f'anchor missing or non-unique in {path}: {old[:90]!r}')
    path.write_text(text.replace(old, new, 1))


models = ROOT / 'lib/features/auto_trade/domain/local_live_trade_models.dart'
replace_once(
    models,
    "    this.openPositionCount = 0,\n    this.closedPositionCount = 0,\n",
    "    this.openPositionCount = 0,\n    this.managedPositionCount = 0,\n    this.unmanagedPositionCount = 0,\n    this.unmanagedSymbols = const [],\n    this.entryBlockReason,\n    this.closedPositionCount = 0,\n",
)
replace_once(
    models,
    "  final int openPositionCount;\n  final int closedPositionCount;\n",
    "  /// Authoritative number of currently open Bitunix positions.\n  final int openPositionCount;\n\n  /// Positions whose durable Local Live ownership was verified on this device.\n  final int managedPositionCount;\n\n  /// Exchange positions that consume slots but are not yet safely recovered.\n  final int unmanagedPositionCount;\n  final List<String> unmanagedSymbols;\n  final String? entryBlockReason;\n  final int closedPositionCount;\n",
)
replace_once(
    models,
    "  bool get canResumeEntries =>\n      state == LocalLiveTradeState.managingOnly &&\n      !entriesEnabled &&\n      openPositionCount == 0;\n",
    "  bool get requiresExchangeRecovery => unmanagedPositionCount > 0;\n\n  bool get canResumeEntries =>\n      state == LocalLiveTradeState.managingOnly &&\n      !entriesEnabled &&\n      entryBlockReason == null &&\n      unmanagedPositionCount == 0 &&\n      managedPositionCount == openPositionCount;\n",
)
replace_once(
    models,
    "    'openPositionCount': openPositionCount,\n    'closedPositionCount': closedPositionCount,\n",
    "    'openPositionCount': openPositionCount,\n    'managedPositionCount': managedPositionCount,\n    'unmanagedPositionCount': unmanagedPositionCount,\n    'unmanagedSymbols': unmanagedSymbols,\n    'entryBlockReason': entryBlockReason,\n    'closedPositionCount': closedPositionCount,\n",
)
replace_once(
    models,
    "    openPositionCount: (json['openPositionCount'] as num?)?.toInt() ?? 0,\n    closedPositionCount: (json['closedPositionCount'] as num?)?.toInt() ?? 0,\n",
    "    openPositionCount: (json['openPositionCount'] as num?)?.toInt() ?? 0,\n    managedPositionCount:\n        (json['managedPositionCount'] as num?)?.toInt() ??\n        (json['openPositionCount'] as num?)?.toInt() ??\n        0,\n    unmanagedPositionCount:\n        (json['unmanagedPositionCount'] as num?)?.toInt() ?? 0,\n    unmanagedSymbols: List.unmodifiable(\n      (json['unmanagedSymbols'] as List<Object?>? ?? const [])\n          .map((item) => item.toString())\n          .where((item) => item.trim().isNotEmpty),\n    ),\n    entryBlockReason: json['entryBlockReason']?.toString(),\n    closedPositionCount: (json['closedPositionCount'] as num?)?.toInt() ?? 0,\n",
)

controller = ROOT / 'lib/features/auto_trade/application/local_live_trade_controller.dart'
preserve_old = "        openPositionCount: _status.openPositionCount,\n        closedPositionCount: _status.closedPositionCount,\n"
preserve_new = "        openPositionCount: _status.openPositionCount,\n        managedPositionCount: _status.managedPositionCount,\n        unmanagedPositionCount: _status.unmanagedPositionCount,\n        unmanagedSymbols: _status.unmanagedSymbols,\n        entryBlockReason: _status.entryBlockReason,\n        closedPositionCount: _status.closedPositionCount,\n"
replace_once(controller, preserve_old, preserve_new)
replace_once(
    controller,
    "      _status = LocalLiveTradeStatus(\n        state: LocalLiveTradeState.starting,\n        updatedAt: DateTime.now().toUtc(),\n        message: entriesEnabled\n            ? 'Local live service is starting on this device.'\n            : 'Local live service is starting in management-only quarantine.',\n        entriesEnabled: entriesEnabled,\n      );\n",
    "      final exchangePositions = account.positions\n          .where((position) => position.quantity > 0)\n          .toList(growable: false);\n      _status = LocalLiveTradeStatus(\n        state: LocalLiveTradeState.starting,\n        updatedAt: DateTime.now().toUtc(),\n        message: exchangePositions.isNotEmpty\n            ? 'Local live service is verifying exchange-position ownership and protection.'\n            : entriesEnabled\n            ? 'Local live service is starting on this device.'\n            : 'Local live service is starting in management-only quarantine.',\n        openPositionCount: exchangePositions.length,\n        managedPositionCount: 0,\n        unmanagedPositionCount: exchangePositions.length,\n        unmanagedSymbols: List.unmodifiable(\n          exchangePositions\n              .map((position) => position.symbol.trim().toUpperCase())\n              .where((symbol) => symbol.isNotEmpty)\n              .toSet(),\n        ),\n        entryBlockReason: exchangePositions.isEmpty\n            ? null\n            : 'exchangeTruthPendingLocalRecovery',\n        entriesEnabled: entriesEnabled && exchangePositions.isEmpty,\n      );\n",
)
replace_once(controller, preserve_old, preserve_new)

ui = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
replace_once(
    ui,
    "    final hasExistingPosition =\n        widget.accountController.snapshot?.positions.isNotEmpty ?? false;\n    final phaseOneStartBlocked = phaseOneQuarantine && !hasExistingPosition;\n",
    "    final exchangeOpenPositions =\n        widget.accountController.snapshot?.positions\n            .where((position) => position.quantity > 0)\n            .toList(growable: false) ??\n        const <AutoTradePosition>[];\n    final hasExistingPosition = exchangeOpenPositions.isNotEmpty;\n    final authoritativeOpenCount = math.max(\n      status.openPositionCount,\n      exchangeOpenPositions.length,\n    );\n    final unrecoveredCount = math.max(\n      status.unmanagedPositionCount,\n      authoritativeOpenCount - status.managedPositionCount,\n    );\n    final unrecoveredSymbols = status.unmanagedSymbols.isNotEmpty\n        ? status.unmanagedSymbols\n        : exchangeOpenPositions\n              .map((position) => position.symbol.trim().toUpperCase())\n              .where((symbol) => symbol.isNotEmpty)\n              .toSet()\n              .toList(growable: false);\n    final phaseOneStartBlocked = phaseOneQuarantine && !hasExistingPosition;\n",
)
replace_once(
    ui,
    "          if (widget.controller.error != null) ...[\n",
    "          if (unrecoveredCount > 0) ...[\n            const SizedBox(height: 10),\n            _BoundaryNotice(\n              text: _t(\n                'Bitunix تعداد $authoritativeOpenCount پوزیشن باز گزارش می‌کند، اما مالکیت محلی $unrecoveredCount پوزیشن (${unrecoveredSymbols.join(', ')}) بعد از حذف برنامه از بین رفته است. این پوزیشن‌ها اسلات و بودجه را اشغال می‌کنند؛ ورود جدید تا بازیابی امن یا بسته‌شدن در صرافی مسدود می‌ماند.',\n                'Bitunix reports $authoritativeOpenCount open position(s), but local ownership for $unrecoveredCount (${unrecoveredSymbols.join(', ')}) was lost after reinstall. These positions consume slots and budget; new entries stay blocked until secure recovery or exchange closure.',\n              ),\n              color: QuantaraColors.warning,\n            ),\n          ],\n          if (widget.controller.error != null) ...[\n",
)
replace_once(
    ui,
    "                  '${status.openPositionCount}/$_maximumConcurrentPositions پوزیشن باز',\n                  '${status.openPositionCount}/$_maximumConcurrentPositions open',\n                ),\n                color: status.openPositionCount > 0\n",
    "                  '$authoritativeOpenCount/$_maximumConcurrentPositions پوزیشن صرافی',\n                  '$authoritativeOpenCount/$_maximumConcurrentPositions exchange open',\n                ),\n                color: authoritativeOpenCount > 0\n",
)
replace_once(
    ui,
    "              if (status.portfolioBudget != null)\n                StatusPill(\n",
    "              StatusPill(\n                label: _t(\n                  '${status.managedPositionCount} تحت مدیریت Quantara',\n                  '${status.managedPositionCount} Quantara-managed',\n                ),\n                color: status.managedPositionCount == authoritativeOpenCount\n                    ? QuantaraColors.cyan\n                    : QuantaraColors.warning,\n              ),\n              if (unrecoveredCount > 0)\n                StatusPill(\n                  label: _t(\n                    '$unrecoveredCount نیازمند بازیابی امن',\n                    '$unrecoveredCount secure recovery pending',\n                  ),\n                  color: QuantaraColors.warning,\n                  icon: Icons.sync_lock_rounded,\n                ),\n              if (status.portfolioBudget != null)\n                StatusPill(\n",
)
replace_once(
    ui,
    "                    phaseOneQuarantine && hasExistingPosition\n                        ? _t('شروع مدیریت', 'Start management')\n                        : canResumeEntries\n                        ? _t('ازسرگیری ورود', 'Resume entries')\n                        : _t('شروع ترید', 'Start trading'),\n",
    "                    unrecoveredCount > 0\n                        ? serviceActive\n                              ? _t(\n                                  'در انتظار بازیابی امن',\n                                  'Secure recovery pending',\n                                )\n                              : _t(\n                                  'شروع بازیابی و مدیریت امن',\n                                  'Start secure recovery',\n                                )\n                        : phaseOneQuarantine && hasExistingPosition\n                        ? _t('شروع مدیریت', 'Start management')\n                        : canResumeEntries\n                        ? _t('ازسرگیری ورود', 'Resume entries')\n                        : _t('شروع ترید', 'Start trading'),\n",
)

print('issue 166 status/controller/UI patch applied')
