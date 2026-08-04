from pathlib import Path

path = Path(
    "src/client/quantara_app/lib/features/auto_trade/application/"
    "local_live_portfolio_risk_runtime.dart"
)
text = path.read_text()

old = """      if (decision.allowed) {
        ledger = ledger.reserve(
          candidate: candidate,
          decision: decision,
          createdAt: now.toUtc(),
        );
      }
"""
new = """      if (decision.allowed) {
        decision = PortfolioEntryDecision(
          allowed: true,
          liveExecutionAllowed: true,
          reason: PortfolioEntryBlockReason.none,
          maximumLoss: decision.maximumLoss,
          requiredMargin: decision.requiredMargin,
          availableRiskBefore: decision.availableRiskBefore,
          availableRiskAfter: decision.availableRiskAfter,
          availableMarginAfter: decision.availableMarginAfter,
        );
        ledger = ledger.reserve(
          candidate: candidate,
          decision: decision,
          createdAt: now.toUtc(),
        );
      }
"""
count = text.count(old)
if count != 1:
    raise RuntimeError(f"live gate anchor: expected 1, found {count}")
path.write_text(text.replace(old, new))
