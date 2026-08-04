from pathlib import Path

path = Path(
    "src/client/quantara_app/lib/features/auto_trade/application/"
    "local_live_trade_service.dart"
)
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 anchor, found {count}")
    text = text.replace(old, new)


replace_once(
    "import '../domain/local_live_cycle_readiness.dart';\n"
    "import '../domain/local_live_trade_models.dart';",
    "import '../domain/local_live_cycle_readiness.dart';\n"
    "import '../domain/local_live_portfolio_admission.dart';\n"
    "import '../domain/local_live_trade_models.dart';",
    "admission import",
)
replace_once(
    "import 'profit_lock_promotion_executor.dart';",
    "import 'local_live_portfolio_execution_guard.dart';\n"
    "import 'profit_lock_promotion_executor.dart';",
    "guard import",
)
replace_once(
    "  final LocalLiveJournalObserver _journalObserver = "
    "LocalLiveJournalObserver();",
    "  final LocalLiveJournalObserver _journalObserver = "
    "LocalLiveJournalObserver();\n"
    "  LocalLivePortfolioExecutionGuard? _portfolioGuard;",
    "guard field",
)
replace_once(
    "          _sessionStartEquity = null;\n"
    "          _sessionPnlProjection = null;",
    "          _sessionStartEquity = null;\n"
    "          _sessionPnlProjection = null;\n"
    "          _portfolioGuard = null;",
    "session reset",
)
replace_once(
    "      await _reconcileManagedPositions(positions, account.authoritativePnl);\n"
    "      final lossPercent =",
    "      await _reconcileManagedPositions(positions, account.authoritativePnl);\n"
    "      if (_sessionStartEquity != null && _sessionStartEquity! > 0) {\n"
    "        _portfolioGuard ??= LocalLivePortfolioExecutionGuard(\n"
    "          dailyRiskLimit:\n"
    "              _sessionStartEquity! * configuration.dailyLossLimitPercent / 100,\n"
    "        );\n"
    "        try {\n"
    "          await _portfolioGuard!.reconcileRestartAndClosedPositions(\n"
    "            managed: _managed,\n"
    "            exchangePositions: positions,\n"
    "            pnlProjection: account.authoritativePnl,\n"
    "            now: DateTime.now().toUtc(),\n"
    "          );\n"
    "        } on LocalLiveTradeSafeException catch (error) {\n"
    "          _entriesEnabled = false;\n"
    "          cycleWarning = error.message;\n"
    "          _auditEvent('portfolio_ledger_block', error.message);\n"
    "        }\n"
    "      }\n"
    "      final lossPercent =",
    "ledger reconcile",
)
replace_once(
    "      if (_entriesEnabled &&\n"
    "          _managed.isEmpty &&\n"
    "          positions.isEmpty &&\n"
    "          account.estimatedEquity > 0) {\n"
    "        await _scanAndMaybeEnter(account);\n"
    "      }",
    "      final exchangePositionCount = positions\n"
    "          .where((item) => item.quantity > 0)\n"
    "          .length;\n"
    "      final hasExecutionSlot = LocalLivePortfolioAdmission.hasExecutionSlot(\n"
    "        configuredMaximum: configuration.maximumConcurrentPositions,\n"
    "        managedPositionCount: _managed.length,\n"
    "        exchangePositionCount: exchangePositionCount,\n"
    "      );\n"
    "      if (_entriesEnabled && hasExecutionSlot && account.estimatedEquity > 0) {\n"
    "        await _scanAndMaybeEnter(account, positions);\n"
    "      } else if (_entriesEnabled && _managed.length != exchangePositionCount) {\n"
    "        _auditEvent(\n"
    "          'portfolio_position_count_block',\n"
    "          'Managed and exchange position counts differ; no new entry was evaluated.',\n"
    "        );\n"
    "      }",
    "scan condition",
)
replace_once(
    "  Future<void> _scanAndMaybeEnter(AutoTradeAccountSnapshot account) async {",
    "  Future<void> _scanAndMaybeEnter(\n"
    "    AutoTradeAccountSnapshot account,\n"
    "    List<BitunixLivePosition> exchangePositions,\n"
    "  ) async {",
    "scan signature",
)
replace_once(
    "      _lastScanAt = DateTime.now().toUtc();\n"
    "      final ideas = <TradeIdea>[",
    "      _lastScanAt = DateTime.now().toUtc();\n"
    "      final occupiedSymbols = exchangePositions\n"
    "          .where((item) => item.quantity > 0)\n"
    "          .map((item) => item.symbol.trim().toUpperCase())\n"
    "          .toSet();\n"
    "      final ideas = <TradeIdea>[",
    "occupied symbols",
)
replace_once(
    "].where((idea) => idea.isActionable).toList(growable: false);",
    "].where(\n"
    "        (idea) =>\n"
    "            idea.isActionable &&\n"
    "            !occupiedSymbols.contains(idea.symbol.trim().toUpperCase()),\n"
    "      ).toList(growable: false);",
    "same symbol filter",
)

path.write_text(text)
