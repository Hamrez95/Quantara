from pathlib import Path

path = Path('src/client/quantara_app/lib/features/cockpit/data/api_cockpit_repository.dart')
text = path.read_text(encoding='utf-8')

replacements = {
    "    if (response.statusCode >= 500) {": "    if (response.statusCode >= 500 ||\n        response.statusCode == 408 ||\n        response.statusCode == 429) {",
    "    final environmentText = _expectString(\n      root,\n      'environment',\n      allowed: const {'demo', 'paper'},\n    );\n    _expectString(\n      root,\n      'dataSourceMode',\n      allowed: const {'deterministic_demo', 'paper_service'},\n    );": "    _expectString(root, 'language', allowed: const {'fa'});\n    _expectString(root, 'environment', allowed: const {'demo'});\n    _expectString(\n      root,\n      'dataSourceMode',\n      allowed: const {'deterministic_demo'},\n    );",
    "    if (environmentText == 'demo' && marketStatusCode != 'demo_not_connected') {": "    if (marketStatusCode != 'demo_not_connected') {",
    "    final analysis = _parseAnalysis(_object(root['analysis'], 'analysis'));\n    final account = _parsePaperAccount(": "    final analysis = _parseAnalysis(_object(root['analysis'], 'analysis'));\n    if (!symbols.contains(analysis.symbol)) {\n      throw const CockpitContractException(\n        'The analysis symbol must exist in the watchlist.',\n      );\n    }\n    final account = _parsePaperAccount(",
    "      environment: environmentText == 'demo'\n          ? AppEnvironment.demo\n          : AppEnvironment.paper,": "      environment: AppEnvironment.demo,",
    "      final impactText = _expectString(\n        factor,": "      _expectString(factor, 'code');\n      final impactText = _expectString(\n        factor,",
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'expected adapter block not found: {old[:100]!r}')
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
