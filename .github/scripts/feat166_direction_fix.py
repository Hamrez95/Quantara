from pathlib import Path

path = Path(
    'src/client/quantara_app/lib/features/auto_trade/application/'
    'local_live_portfolio_risk_runtime.dart'
)
text = path.read_text()
anchor = "import '../../portfolio_risk/domain/portfolio_risk_atomic_store.dart';\n"
if anchor not in text:
    raise SystemExit('runtime import anchor missing')
path.write_text(
    text.replace(
        anchor,
        "import '../../owner_alpha/domain/owner_alpha_models.dart';\n" + anchor,
        1,
    )
)
print('issue 166 direction type wired')
