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
    "import '../domain/profit_lock_stop_policy.dart';\n"
    "import '../domain/trading_pnl_projection.dart';",
    "import '../domain/profit_lock_stop_policy.dart';\n"
    "import '../domain/remaining_target_protection_policy.dart';\n"
    "import '../domain/trading_pnl_projection.dart';",
    "policy import",
)
replace_once(
    "      await portfolioGuard.confirmReduction(\n"
    "        positionId: managed.positionId,\n"
    "        remainingQuantity: position.quantity,\n"
    "        exchangeFillIds: positionPnl.exitFills\n"
    "            .map((item) => item.tradeId)\n"
    "            .where((item) => item.trim().isNotEmpty)\n"
    "            .toSet(),\n"
    "        now: DateTime.now().toUtc(),\n"
    "      );\n"
    "      var next = managed.copyWith(",
    "      final remainingTargetsProtected =\n"
    "          RemainingTargetProtectionPolicy.allRemainingTargetsProtected(\n"
    "            targetOrderIds: managed.targetOrderIds,\n"
    "            targetQuantities: managed.targetQuantities,\n"
    "            filledQuantities: fillProgress.filledQuantities,\n"
    "            pendingProtection: protection\n"
    "                .where((item) => item.takeProfitPrice > 0)\n"
    "                .map(\n"
    "                  (item) => PendingTargetProtectionEvidence(\n"
    "                    orderId: item.orderId,\n"
    "                    triggerPrice: item.takeProfitPrice,\n"
    "                    quantity: item.takeProfitQuantity,\n"
    "                  ),\n"
    "                ),\n"
    "            quantityTolerance: quantityTolerance,\n"
    "          );\n"
    "      if (!remainingTargetsProtected) {\n"
    "        _entriesEnabled = false;\n"
    "        const warning =\n"
    "            'A remaining take-profit tranche is missing or undersized on the exchange; new entries are blocked.';\n"
    "        _replaceManaged(\n"
    "          managed,\n"
    "          managed.copyWith(\n"
    "            profitLockProgress: managed.profitLockProgress.copyWith(\n"
    "              warning: warning,\n"
    "            ),\n"
    "          ),\n"
    "        );\n"
    "        _auditEvent(\n"
    "          'target_ladder_incomplete',\n"
    "          warning,\n"
    "          symbol: managed.symbol,\n"
    "        );\n"
    "        continue;\n"
    "      }\n"
    "      await portfolioGuard.confirmReduction(\n"
    "        positionId: managed.positionId,\n"
    "        remainingQuantity: position.quantity,\n"
    "        exchangeFillIds: positionPnl.exitFills\n"
    "            .map((item) => item.tradeId)\n"
    "            .where((item) => item.trim().isNotEmpty)\n"
    "            .toSet(),\n"
    "        now: DateTime.now().toUtc(),\n"
    "      );\n"
    "      var next = managed.copyWith(",
    "remaining target gate",
)

path.write_text(text)
