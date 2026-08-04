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
    "      await _journalObserver.reconcilePosition(\n"
    "        managed: managed,\n"
    "        positionPnl: positionPnl,\n"
    "        positionClosed: false,\n"
    "      );",
    "      final portfolioGuard = _portfolioGuard;\n"
    "      if (portfolioGuard == null) {\n"
    "        _entriesEnabled = false;\n"
    "        const warning =\n"
    "            'Atomic portfolio ledger is unavailable for managed exposure.';\n"
    "        _auditEvent('portfolio_ledger_block', warning, symbol: managed.symbol);\n"
    "        continue;\n"
    "      }\n"
    "      await portfolioGuard.confirmStop(\n"
    "        positionId: managed.positionId,\n"
    "        confirmedStop: currentStop,\n"
    "        now: DateTime.now().toUtc(),\n"
    "      );\n"
    "      await _journalObserver.reconcilePosition(\n"
    "        managed: managed,\n"
    "        positionPnl: positionPnl,\n"
    "        positionClosed: false,\n"
    "      );",
    "confirm current stop",
)
replace_once(
    "      final fillProgress = ConfirmedTargetFillProgress.reconcile(\n"
    "        targetOrderIds: managed.targetOrderIds,\n"
    "        targetQuantities: managed.targetQuantities,\n"
    "        exchangeExitFills: positionPnl.exitFills,\n"
    "        processedTradeIds: managed.profitLockProgress.processedTradeIds,\n"
    "        quantityTolerance: quantityTolerance,\n"
    "        observedRemainingQuantity: position.quantity,\n"
    "      );",
    "      final fillProgress = ConfirmedTargetFillProgress.reconcile(\n"
    "        targetOrderIds: managed.targetOrderIds,\n"
    "        targetQuantities: managed.targetQuantities,\n"
    "        exchangeExitFills: positionPnl.exitFills,\n"
    "        processedTradeIds: managed.profitLockProgress.processedTradeIds,\n"
    "        quantityTolerance: quantityTolerance,\n"
    "        observedRemainingQuantity: position.quantity,\n"
    "      );\n"
    "      await portfolioGuard.confirmReduction(\n"
    "        positionId: managed.positionId,\n"
    "        remainingQuantity: position.quantity,\n"
    "        exchangeFillIds: positionPnl.exitFills\n"
    "            .map((item) => item.tradeId)\n"
    "            .where((item) => item.trim().isNotEmpty)\n"
    "            .toSet(),\n"
    "        now: DateTime.now().toUtc(),\n"
    "      );",
    "confirm exchange reduction",
)
replace_once(
    "          _auditEvent(\n"
    "            pendingStage == 1 ? 'risk_free_confirmed' : 'runner_confirmed',\n"
    "            'Pending stop promotion was confirmed from exchange protection truth.',\n"
    "            symbol: next.symbol,\n"
    "          );",
    "          await portfolioGuard.confirmStop(\n"
    "            positionId: next.positionId,\n"
    "            confirmedStop: currentStop,\n"
    "            now: DateTime.now().toUtc(),\n"
    "          );\n"
    "          _auditEvent(\n"
    "            pendingStage == 1 ? 'risk_free_confirmed' : 'runner_confirmed',\n"
    "            'Pending stop promotion was confirmed from exchange protection truth.',\n"
    "            symbol: next.symbol,\n"
    "          );",
    "confirm pending promotion risk",
)
replace_once(
    "            currentStop;\n"
    "      }\n\n"
    "      if (next.profitLockProgress.confirmedStage >= 1 &&\n"
    "          next.profitLockProgress.confirmedStage < 2 &&",
    "            currentStop;\n"
    "        if (next.profitLockProgress.confirmedStage >= 1 &&\n"
    "            !next.profitLockProgress.hasPendingPromotion) {\n"
    "          await portfolioGuard.confirmStop(\n"
    "            positionId: next.positionId,\n"
    "            confirmedStop: currentStop,\n"
    "            now: DateTime.now().toUtc(),\n"
    "          );\n"
    "        }\n"
    "      }\n\n"
    "      if (next.profitLockProgress.confirmedStage >= 1 &&\n"
    "          next.profitLockProgress.confirmedStage < 2 &&",
    "confirm TP1 stop risk",
)
replace_once(
    "        next = await _promoteStopAfterConfirmedTarget(\n"
    "          original: managed,\n"
    "          current: next,\n"
    "          position: position,\n"
    "          stage: 2,\n"
    "          decision: decision,\n"
    "          previousStop: currentStop,\n"
    "          priceTolerance: priceTolerance,\n"
    "          quantityTolerance: quantityTolerance,\n"
    "        );\n"
    "      }",
    "        next = await _promoteStopAfterConfirmedTarget(\n"
    "          original: managed,\n"
    "          current: next,\n"
    "          position: position,\n"
    "          stage: 2,\n"
    "          decision: decision,\n"
    "          previousStop: currentStop,\n"
    "          priceTolerance: priceTolerance,\n"
    "          quantityTolerance: quantityTolerance,\n"
    "        );\n"
    "        if (next.profitLockProgress.confirmedStage >= 2 &&\n"
    "            !next.profitLockProgress.hasPendingPromotion) {\n"
    "          final latestProtection = await exchange.fetchPendingProtection(\n"
    "            credentials,\n"
    "            symbol: next.symbol,\n"
    "            positionId: next.positionId,\n"
    "          );\n"
    "          final latestStop = _confirmedStopPrice(\n"
    "            managed: next,\n"
    "            protection: latestProtection,\n"
    "            remainingQuantity: position.quantity,\n"
    "            quantityTolerance: quantityTolerance,\n"
    "          );\n"
    "          if (latestStop == null) {\n"
    "            throw const LocalLiveTradeSafeException(\n"
    "              'Promoted runner stop was not exchange-confirmed.',\n"
    "            );\n"
    "          }\n"
    "          await portfolioGuard.confirmStop(\n"
    "            positionId: next.positionId,\n"
    "            confirmedStop: latestStop,\n"
    "            now: DateTime.now().toUtc(),\n"
    "          );\n"
    "        }\n"
    "      }",
    "confirm TP2 stop risk",
)

path.write_text(text)
