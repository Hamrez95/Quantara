from pathlib import Path

path = Path('lib/features/auto_trade/application/local_live_trade_service.dart')
text = path.read_text(encoding='utf-8')
old = '''          await portfolioGuard.confirmStop(
            positionId: next.positionId,
            confirmedStop: latestStop,
            now: DateTime.now().toUtc(),
          );
        }
      }
      _replaceManaged(managed, next);
'''
new = '''          await portfolioGuard.confirmStop(
            positionId: next.positionId,
            confirmedStop: latestStop,
            now: DateTime.now().toUtc(),
          );
          currentStop = latestStop;
        }
      }

      if (next.profitLockProgress.confirmedStage >= 2 &&
          fillProgress.tp2Confirmed &&
          !fillProgress.tp3Confirmed &&
          !next.profitLockProgress.hasPendingPromotion) {
        try {
          final markPrice = await exchange.fetchMarkPrice(next.symbol);
          final trail = ProfitLockStopPolicy.runnerTrail(
            direction: next.direction,
            markPrice: markPrice,
            currentConfirmedStop: currentStop,
            tp1Price: next.targets.first,
            initialRiskDistance: (next.entryPrice - next.originalStopLoss).abs(),
            pricePrecision: rules.pricePrecision,
            previousFavorableExtreme:
                next.profitLockProgress.runnerFavorableExtreme,
            scalp: next.timeframe == '5m',
          );
          next = next.copyWith(
            profitLockProgress: next.profitLockProgress.copyWith(
              runnerFavorableExtreme: trail.favorableExtreme,
              clearWarning: true,
            ),
          );
          if (trail.stopDecision.requiresMutation) {
            next = await _promoteStopAfterConfirmedTarget(
              original: managed,
              current: next,
              position: position,
              stage: 2,
              decision: trail.stopDecision,
              previousStop: currentStop,
              priceTolerance: priceTolerance,
              quantityTolerance: quantityTolerance,
            );
            if (next.profitLockProgress.confirmedStage >= 2 &&
                !next.profitLockProgress.hasPendingPromotion) {
              final latestProtection = await exchange.fetchPendingProtection(
                credentials,
                symbol: next.symbol,
                positionId: next.positionId,
              );
              final latestStop = _confirmedStopPrice(
                managed: next,
                protection: latestProtection,
                remainingQuantity: position.quantity,
                quantityTolerance: quantityTolerance,
              );
              if (latestStop == null ||
                  !ProfitLockStopPolicy.isAtLeastAsSafe(
                    direction: next.direction,
                    confirmedStop: latestStop,
                    proposedStop: trail.stopDecision.proposedStop,
                    tolerance: priceTolerance,
                  )) {
                _entriesEnabled = false;
                throw const LocalLiveTradeSafeException(
                  'Runner trail mutation was not exchange-confirmed.',
                );
              }
              currentStop = latestStop;
              await portfolioGuard.confirmStop(
                positionId: next.positionId,
                confirmedStop: latestStop,
                now: DateTime.now().toUtc(),
              );
            }
          }
        } on LocalLiveTradeSafeException {
          rethrow;
        } on Object catch (error) {
          _entriesEnabled = false;
          final warning =
              'Runner trail evidence is unavailable; the existing confirmed stop is preserved and new entries are blocked (${_safeError(error)}).';
          next = next.copyWith(
            profitLockProgress: next.profitLockProgress.copyWith(
              warning: warning,
            ),
          );
          _auditEvent('runner_trail_deferred', warning, symbol: next.symbol);
        }
      }
      _replaceManaged(managed, next);
'''
if old not in text:
    raise SystemExit('expected runner insertion anchor not found')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
