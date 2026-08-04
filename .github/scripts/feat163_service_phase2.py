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
    "      await exchange.ensureIsolatedMargin(\n"
    "        symbol: idea.symbol,\n"
    "        credentials: credentials,\n"
    "      );",
    "      final portfolioGuard = _portfolioGuard;\n"
    "      if (portfolioGuard == null) {\n"
    "        _auditEvent(\n"
    "          'portfolio_ledger_block',\n"
    "          'Atomic portfolio risk runtime is not initialized.',\n"
    "          symbol: idea.symbol,\n"
    "        );\n"
    "        return;\n"
    "      }\n"
    "      final existingExposureProtected =\n"
    "          _managed.length ==\n"
    "              exchangePositions.where((item) => item.quantity > 0).length &&\n"
    "          _managed.every(\n"
    "            (item) => item.profitLockProgress.warning == null,\n"
    "          );\n"
    "      final reservation = await portfolioGuard.reserve(\n"
    "        idea: idea,\n"
    "        plannedQuantity: quantity,\n"
    "        entryPrice: entryPrice,\n"
    "        stopPrice: stopLoss,\n"
    "        requiredMargin: requiredMargin,\n"
    "        leverage: leverage,\n"
    "        minimumQuantity: rules.minimumQuantity,\n"
    "        minimumNotional: rules.minimumQuantity * entryPrice,\n"
    "        account: account,\n"
    "        allOpenPositionsProtected: existingExposureProtected,\n"
    "        now: DateTime.now().toUtc(),\n"
    "      );\n"
    "      if (!reservation.decision.allowed ||\n"
    "          !reservation.decision.liveExecutionAllowed) {\n"
    "        _auditEvent(\n"
    "          'portfolio_reservation_block',\n"
    "          'Portfolio reservation rejected: ${reservation.decision.reason.name}.',\n"
    "          symbol: idea.symbol,\n"
    "        );\n"
    "        return;\n"
    "      }\n"
    "      String? activeReservationId = 'local-live:${idea.setupId}';\n"
    "      var orderRequestStarted = false;\n"
    "      try {\n"
    "        await exchange.ensureIsolatedMargin(\n"
    "          symbol: idea.symbol,\n"
    "          credentials: credentials,\n"
    "        );",
    "reserve before order",
)
replace_once(
    "      final placed = await exchange.placeMarketEntry(\n"
    "        symbol: idea.symbol,",
    "      orderRequestStarted = true;\n"
    "      final placed = await exchange.placeMarketEntry(\n"
    "        symbol: idea.symbol,",
    "order request boundary",
)
replace_once(
    "          if (position != null && position.quantity > 0) {\n"
    "            await exchange.closePositionReduceOnly(",
    "          if (position != null && position.quantity > 0) {\n"
    "            await portfolioGuard.recordFill(\n"
    "              reservationId: activeReservationId!,\n"
    "              orderId: placed.orderId,\n"
    "              positionId: position.positionId,\n"
    "              fillQuantity: position.quantity,\n"
    "              now: DateTime.now().toUtc(),\n"
    "            );\n"
    "            await exchange.closePositionReduceOnly(",
    "record unresolved partial fill",
)
replace_once(
    "          _executedSetupIds.add(idea.setupId);\n"
    "          await _persistState();\n"
    "          throw const LocalLiveTradeSafeException(",
    "          if (position == null && detail?.status == 'CANCELED') {\n"
    "            await portfolioGuard.releaseNoExposure(\n"
    "              reservationId: activeReservationId!,\n"
    "              evidence: 'entry-canceled-without-position',\n"
    "              now: DateTime.now().toUtc(),\n"
    "            );\n"
    "            activeReservationId = null;\n"
    "          }\n"
    "          _executedSetupIds.add(idea.setupId);\n"
    "          await _persistState();\n"
    "          throw const LocalLiveTradeSafeException(",
    "release canceled no exposure",
)
replace_once(
    "      quantity = rules.roundQuantityDown(\n"
    "        math.min(detail.filledQuantity, position.quantity),\n"
    "      );",
    "      await portfolioGuard.recordFill(\n"
    "        reservationId: activeReservationId!,\n"
    "        orderId: placed.orderId,\n"
    "        positionId: position.positionId,\n"
    "        fillQuantity: math.min(detail.filledQuantity, position.quantity),\n"
    "        now: DateTime.now().toUtc(),\n"
    "      );\n"
    "      quantity = rules.roundQuantityDown(\n"
    "        math.min(detail.filledQuantity, position.quantity),\n"
    "      );",
    "record confirmed fill",
)
replace_once(
    "      if (!protections.any((item) => item.stopLossPrice > 0)) {\n"
    "        await exchange.closePositionReduceOnly(\n"
    "          position: position,\n"
    "          clientId: '$clientId-unprotected-close',\n"
    "          credentials: credentials,\n"
    "        );\n"
    "        throw const LocalLiveTradeSafeException(\n"
    "          'Protective stop was not confirmed; the position was closed reduce-only.',\n"
    "        );\n"
    "      }\n"
    "      final allocation =",
    "      if (!protections.any((item) => item.stopLossPrice > 0)) {\n"
    "        await exchange.closePositionReduceOnly(\n"
    "          position: position,\n"
    "          clientId: '$clientId-unprotected-close',\n"
    "          credentials: credentials,\n"
    "        );\n"
    "        throw const LocalLiveTradeSafeException(\n"
    "          'Protective stop was not confirmed; the position was closed reduce-only.',\n"
    "        );\n"
    "      }\n"
    "      await portfolioGuard.confirmStop(\n"
    "        positionId: position.positionId,\n"
    "        confirmedStop: stopLoss,\n"
    "        now: DateTime.now().toUtc(),\n"
    "      );\n"
    "      final allocation =",
    "confirm initial stop",
)
replace_once(
    "      _auditEvent(\n"
    "        'position_protected',\n"
    "        'Entry fill, full stop and three staged targets confirmed '\n"
    "            '(${(configuration.targetAllocation.tp1Fraction * 100).toStringAsFixed(0)}/'\n"
    "            '${(configuration.targetAllocation.tp2Fraction * 100).toStringAsFixed(0)}/'\n"
    "            '${(configuration.targetAllocation.tp3Fraction * 100).toStringAsFixed(0)}%; '\n"
    "            'qty ${targetQuantities.map((item) => item.toString()).join('/')}; '\n"
    "            '${profitPlan.profile.name}).',\n"
    "        symbol: idea.symbol,\n"
    "      );\n"
    "    } finally {",
    "      _auditEvent(\n"
    "        'position_protected',\n"
    "        'Entry fill, full stop and three staged targets confirmed '\n"
    "            '(${(configuration.targetAllocation.tp1Fraction * 100).toStringAsFixed(0)}/'\n"
    "            '${(configuration.targetAllocation.tp2Fraction * 100).toStringAsFixed(0)}/'\n"
    "            '${(configuration.targetAllocation.tp3Fraction * 100).toStringAsFixed(0)}%; '\n"
    "            'qty ${targetQuantities.map((item) => item.toString()).join('/')}; '\n"
    "            '${profitPlan.profile.name}).',\n"
    "        symbol: idea.symbol,\n"
    "      );\n"
    "      } on Object catch (error) {\n"
    "        final reservationId = activeReservationId;\n"
    "        if (reservationId != null) {\n"
    "          if (orderRequestStarted) {\n"
    "            await portfolioGuard.markAmbiguous(\n"
    "              reservationId: reservationId,\n"
    "              evidence: 'entry-lifecycle:${error.runtimeType}',\n"
    "              now: DateTime.now().toUtc(),\n"
    "            );\n"
    "          } else {\n"
    "            await portfolioGuard.releaseNoExposure(\n"
    "              reservationId: reservationId,\n"
    "              evidence: 'pre-order:${error.runtimeType}',\n"
    "              now: DateTime.now().toUtc(),\n"
    "            );\n"
    "          }\n"
    "        }\n"
    "        rethrow;\n"
    "      }\n"
    "    } finally {",
    "reservation cleanup catch",
)

path.write_text(text)
