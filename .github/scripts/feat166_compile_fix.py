from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'anchor missing in {path}: {old[:90]!r}')
    path.write_text(text.replace(old, new, 1))


recovery = ROOT / 'lib/features/auto_trade/application/local_live_orphan_recovery.dart'
replace_once(
    recovery,
    "import '../../owner_alpha/domain/owner_alpha_models.dart';\n",
    "import '../../market_analysis/domain/market_regime_models.dart';\nimport '../../owner_alpha/domain/owner_alpha_models.dart';\n",
)

runtime = ROOT / 'lib/features/auto_trade/application/local_live_portfolio_risk_runtime.dart'
replace_once(
    runtime,
    "import '../domain/local_live_portfolio_admission.dart';\n",
    "import '../domain/local_live_portfolio_admission.dart';\nimport '../domain/local_live_trade_models.dart';\n",
)

guard = ROOT / 'lib/features/auto_trade/application/local_live_portfolio_execution_guard.dart'
delegate = '''  Future<PortfolioRiskLedger> adoptVerifiedOpenPosition({
    required LocalLiveManagedPosition managed,
    required double confirmedStop,
    required DateTime now,
  }) => _runtime.adoptVerifiedOpenPosition(
    managed: managed,
    confirmedStop: confirmedStop,
    now: now,
  );

'''
replace_once(
    guard,
    '  Future<void> releaseNoExposure({\n',
    delegate + '  Future<void> releaseNoExposure({\n',
)

print('issue 166 compile wiring applied')
