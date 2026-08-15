from pathlib import Path

path = Path('src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart')
text = path.read_text()
needle = "import '../domain/local_live_trade_models.dart';\n"
insert = needle + "import '../domain/private_truth_models.dart';\n"
if "import '../domain/private_truth_models.dart';" not in text:
    if needle not in text:
        raise SystemExit('local_live_trade_models import not found')
    path.write_text(text.replace(needle, insert, 1))
