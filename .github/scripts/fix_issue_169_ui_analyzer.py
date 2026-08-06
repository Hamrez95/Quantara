from pathlib import Path

path = Path(
    'src/client/quantara_app/lib/features/owner_alpha/presentation/'
    'owner_alpha_page.dart'
)
text = path.read_text(encoding='utf-8')
needle = "import 'dart:typed_data';\n"
if text.count(needle) != 1:
    raise RuntimeError(f'expected one typed_data import, found {text.count(needle)}')
path.write_text(text.replace(needle, '', 1), encoding='utf-8')
