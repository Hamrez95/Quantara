from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'anchor missing in {path}: {old[:100]!r}')
    path.write_text(text.replace(old, new, 1))


policy = ROOT / 'lib/features/auto_trade/application/local_live_orphan_recovery.dart'
replace_once(
    policy,
    "    if (pnl == null) {\n      return blocked('Position fill history is unavailable.');\n    }\n",
    "    if (pnl == null) {\n      return blocked('Position fill history is unavailable.');\n    }\n    if (!pnl.isVerified) {\n      return blocked('Position fill history is not exchange-verified.');\n    }\n",
)

controller = ROOT / 'lib/features/auto_trade/application/local_live_trade_controller.dart'
replace_once(
    controller,
    '  Future<bool> start(LocalLiveTradeConfiguration configuration) async {\n',
    '  Future<bool> start(\n    LocalLiveTradeConfiguration configuration, {\n    bool recoveryOnly = false,\n  }) async {\n',
)
replace_once(
    controller,
    "      final account = _accountController.snapshot;\n      if (!reconciled ||\n          account == null ||\n          _accountController.reconciliation.blocksNewEntries) {\n        throw const LocalLiveTradeSafeException(\n          'New entries are blocked until a fresh, coherent Bitunix private-account reconciliation succeeds.',\n        );\n      }\n\n      final entriesEnabled = ExchangeTruthPhaseOneGate.realEntriesAllowed;\n",
    "      final account = _accountController.snapshot;\n      final reconciliation = _accountController.reconciliation;\n      final completedAt = reconciliation.completedAt;\n      final freshDivergenceForRecovery =\n          recoveryOnly &&\n          account != null &&\n          account.positions.any((position) => position.quantity > 0) &&\n          reconciliation.health ==\n              PrivateAccountReconciliationHealth.divergent &&\n          completedAt != null &&\n          DateTime.now().toUtc().difference(completedAt).abs() <=\n              const Duration(seconds: 20);\n      if (account == null ||\n          (!reconciled && !freshDivergenceForRecovery) ||\n          (!recoveryOnly && reconciliation.blocksNewEntries)) {\n        throw const LocalLiveTradeSafeException(\n          'New entries are blocked until a fresh, coherent Bitunix private-account reconciliation succeeds.',\n        );\n      }\n      if (recoveryOnly &&\n          !account.positions.any((position) => position.quantity > 0)) {\n        throw const LocalLiveTradeSafeException(\n          'No open Bitunix position is available for secure recovery.',\n        );\n      }\n\n      final entriesEnabled =\n          ExchangeTruthPhaseOneGate.realEntriesAllowed && !recoveryOnly;\n",
)
replace_once(
    controller,
    "        message: exchangePositions.isNotEmpty\n            ? 'Local live service is verifying exchange-position ownership and protection.'\n",
    "        message: exchangePositions.isNotEmpty\n            ? recoveryOnly\n                  ? 'Local live service is recovering exchange-position ownership in management-only mode.'\n                  : 'Local live service is verifying exchange-position ownership and protection.'\n",
)

ui = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
replace_once(
    ui,
    "                      ? null\n                      : _confirmStart,\n",
    "                      ? null\n                      : () => _confirmStart(\n                          recoveryOnly: unrecoveredCount > 0,\n                        ),\n",
)
replace_once(
    ui,
    '  Future<void> _confirmStart() async {\n',
    '  Future<void> _confirmStart({bool recoveryOnly = false}) async {\n',
)
replace_once(
    ui,
    "    if (_enabledSymbols.isEmpty || _enabledTimeframes.isEmpty) {\n",
    "    if (!recoveryOnly &&\n        (_enabledSymbols.isEmpty || _enabledTimeframes.isEmpty)) {\n",
)
replace_once(
    ui,
    "    if (_riskPercent > 0.50 || _dailyLossLimit > 3 || _leverage > 25) {\n",
    "    if (!recoveryOnly &&\n        (_riskPercent > 0.50 || _dailyLossLimit > 3 || _leverage > 25)) {\n",
)
replace_once(
    ui,
    "        title: Text(_t('فعال‌سازی پول واقعی', 'Enable real-money canary')),\n",
    "        title: Text(\n          recoveryOnly\n              ? _t(\n                  'بازیابی امن پوزیشن موجود',\n                  'Securely recover existing position',\n                )\n              : _t('فعال‌سازی پول واقعی', 'Enable real-money canary'),\n        ),\n",
)
replace_once(
    ui,
    "                  'Quantara اجازه ارسال سفارش واقعی فیوچرز خواهد داشت. شروع فقط از همین صفحه انجام می‌شود و بعد از ری‌استارت گوشی خودکار فعال نمی‌شود.',\n                  'Quantara will be allowed to submit real futures orders. It starts only from this visible screen and never auto-arms after a device reboot.',\n",
    "                  recoveryOnly\n                      ? 'Quantara فقط مالکیت، تاریخچه و حفاظت پوزیشن باز موجود را از Bitunix بررسی و بازسازی می‌کند. در این مرحله هیچ ورود جدیدی مسلح یا ارسال نمی‌شود.'\n                      : 'Quantara اجازه ارسال سفارش واقعی فیوچرز خواهد داشت. شروع فقط از همین صفحه انجام می‌شود و بعد از ری‌استارت گوشی خودکار فعال نمی‌شود.',\n                  recoveryOnly\n                      ? 'Quantara will only verify and reconstruct ownership, history, and protection for the existing Bitunix position. No new entry is armed or submitted during recovery.'\n                      : 'Quantara will be allowed to submit real futures orders. It starts only from this visible screen and never auto-arms after a device reboot.',\n",
)
replace_once(
    ui,
    "                  'تأیید می‌کنم کلید API دسترسی برداشت/انتقال ندارد و اولین اجرا را با موجودی کم انجام می‌دهم.',\n                  'I confirm the API key has no withdrawal/transfer permission and I will use a small balance for the first canary.',\n",
    "                  recoveryOnly\n                      ? 'تأیید می‌کنم این مرحله فقط برای بازیابی و مدیریت پوزیشن موجود است و فعال‌سازی ورودهای جدید را جداگانه انجام خواهم داد.'\n                      : 'تأیید می‌کنم کلید API دسترسی برداشت/انتقال ندارد و اولین اجرا را با موجودی کم انجام می‌دهم.',\n                  recoveryOnly\n                      ? 'I confirm this step is only for recovering and managing the existing position; I will arm new entries separately.'\n                      : 'I confirm the API key has no withdrawal/transfer permission and I will use a small balance for the first canary.',\n",
)
replace_once(
    ui,
    "            child: Text(_t('تأیید و شروع', 'Confirm & start')),\n",
    "            child: Text(\n              recoveryOnly\n                  ? _t('تأیید و بازیابی', 'Confirm & recover')\n                  : _t('تأیید و شروع', 'Confirm & start'),\n            ),\n",
)
replace_once(
    ui,
    "    final started = await widget.controller.start(\n      LocalLiveTradeConfiguration(\n        symbols: _enabledSymbols.toList(growable: false),\n        timeframes: _enabledTimeframes.toList(growable: false),\n",
    "    final recoverySymbols =\n        widget.accountController.snapshot?.positions\n            .where((position) => position.quantity > 0)\n            .map((position) => position.symbol.trim().toUpperCase())\n            .where((symbol) => symbol.isNotEmpty)\n            .toSet()\n            .toList(growable: false) ??\n        const <String>[];\n    final started = await widget.controller.start(\n      LocalLiveTradeConfiguration(\n        symbols: recoveryOnly\n            ? recoverySymbols\n            : _enabledSymbols.toList(growable: false),\n        timeframes: recoveryOnly && _enabledTimeframes.isEmpty\n            ? const ['15m']\n            : _enabledTimeframes.toList(growable: false),\n",
)
replace_once(
    ui,
    "        targetAllocation: _targetAllocation,\n      ),\n    );\n",
    "        targetAllocation: _targetAllocation,\n      ),\n      recoveryOnly: recoveryOnly,\n    );\n",
)
replace_once(
    ui,
    "                'ورود جدید متوقف است و هیچ پوزیشن بازی برای مدیریت وجود ندارد. برای فعال‌سازی دوباره، دکمه «ازسرگیری ورود» را بزن و همه تأییدهای پول واقعی را دوباره انجام بده.',\n                'New entries are stopped and there is no open position to manage. Use Resume entries and repeat every real-money confirmation to arm entries again.',\n",
    "                status.openPositionCount == 0\n                    ? 'ورود جدید متوقف است و هیچ پوزیشن بازی برای مدیریت وجود ندارد. برای فعال‌سازی دوباره، دکمه «ازسرگیری ورود» را بزن و همه تأییدهای پول واقعی را دوباره انجام بده.'\n                    : 'پوزیشن موجود با حقیقت صرافی بازیابی و تحت مدیریت قرار گرفته است؛ ورودهای جدید هنوز خاموش‌اند. فقط برای مسلح‌کردن ورودی‌های بعدی «ازسرگیری ورود» را جداگانه تأیید کن.',\n                status.openPositionCount == 0\n                    ? 'New entries are stopped and there is no open position to manage. Use Resume entries and repeat every real-money confirmation to arm entries again.'\n                    : 'The existing position is recovered and managed from exchange truth; new entries are still off. Confirm Resume entries separately only when you intend to arm future entries.',\n",
)

# Add source-level safety coverage without weakening behavioral tests.
source_test = ROOT / 'test/local_live_orphan_recovery_source_test.dart'
replace_once(
    source_test,
    "  test('notification does not claim the exchange is flat during recovery', () {\n",
    "  test('secure recovery starts management-only and requires a later explicit arm', () {\n    final controller = File(\n      'lib/features/auto_trade/application/local_live_trade_controller.dart',\n    ).readAsStringSync();\n    final ui = File(\n      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',\n    ).readAsStringSync();\n    expect(controller, contains('bool recoveryOnly = false'));\n    expect(\n      controller,\n      contains(\n        'ExchangeTruthPhaseOneGate.realEntriesAllowed && !recoveryOnly',\n      ),\n    );\n    expect(ui, contains('recoveryOnly: unrecoveredCount > 0'));\n    expect(ui, contains('Confirm & recover'));\n  });\n\n  test('notification does not claim the exchange is flat during recovery', () {\n",
)

# Verify unverified position history remains fail-closed.
recovery_test = ROOT / 'test/local_live_orphan_recovery_test.dart'
replace_once(
    recovery_test,
    '  PositionPnlProjection projection({bool withExit = false}) {\n',
    '  PositionPnlProjection projection({\n    bool withExit = false,\n    bool sourceVerified = true,\n  }) {\n',
)
replace_once(
    recovery_test,
    '      sourceVerified: true,\n',
    '      sourceVerified: sourceVerified,\n',
)
replace_once(
    recovery_test,
    "  test('refuses incomplete protection', () {\n",
    "  test('refuses unverified exchange history', () {\n    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(\n      position: position,\n      pnl: projection(sourceVerified: false),\n      protection: protection(),\n      entryOrder: quantaraOrder,\n      rules: rules,\n    );\n    expect(decision.allowed, isFalse);\n    expect(decision.reason, contains('not exchange-verified'));\n  });\n\n  test('refuses incomplete protection', () {\n",
)

print('issue 166 management-only recovery hardening applied')
