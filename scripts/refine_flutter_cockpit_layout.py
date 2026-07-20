from pathlib import Path

path = Path('src/client/quantara_app/lib/features/cockpit/presentation/cockpit_page.dart')
text = path.read_text(encoding='utf-8')

replacements = {
    '                    _DemoBanner(snapshot: snapshot),': '                    const _DemoBanner(),',
    "class _DemoBanner extends StatelessWidget {\n  const _DemoBanner({required this.snapshot});\n\n  final CockpitSnapshot snapshot;": "class _DemoBanner extends StatelessWidget {\n  const _DemoBanner();",
    "      trailing: Expanded(\n        child: Align(\n          alignment: Alignment.bottomCenter,\n          child: Padding(\n            padding: const EdgeInsets.only(bottom: 18),\n            child: Tooltip(\n              message: strings.lockedRealMoney,\n              child: Icon(Icons.lock_outline_rounded, color: scheme.error),\n            ),\n          ),\n        ),\n      ),": "      trailing: Padding(\n        padding: const EdgeInsets.only(top: 18),\n        child: Tooltip(\n          message: strings.lockedRealMoney,\n          child: Icon(Icons.lock_outline_rounded, color: scheme.error),\n        ),\n      ),",
    '              final ratio = crossAxisCount == 1 ? 2.45 : 1.45;': '              final ratio = crossAxisCount == 1 ? 1.75 : 1.45;',
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'expected block not found: {old[:80]!r}')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
