from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1))


page = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart"
replace(
    page,
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:http/http.dart' as http;\n",
)
replace(
    page,
    "import '../../market_analysis/domain/market_chart_models.dart';\n",
    "import '../../auto_trade/application/auto_trade_controller.dart';\nimport '../../auto_trade/data/bitunix_private_api_client.dart';\nimport '../../auto_trade/data/secure_auto_trade_credentials_store.dart';\nimport '../../auto_trade/domain/auto_trade_models.dart';\nimport '../../market_analysis/domain/market_chart_models.dart';\n",
)
replace(
    page,
    "part 'owner_alpha_analysis.dart';\npart 'owner_alpha_exchange.dart';",
    "part 'owner_alpha_analysis.dart';\npart 'owner_alpha_auto_trade.dart';\npart 'owner_alpha_exchange.dart';",
)
replace(
    page,
    "  late final OwnerAlphaController _controller = OwnerAlphaController(\n",
    "  late final http.Client _autoTradeHttpClient = http.Client();\n  late final AutoTradeController _autoTradeController = AutoTradeController(\n    apiClient: BitunixPrivateApiClient(client: _autoTradeHttpClient),\n    credentialsStore: const SecureAutoTradeCredentialsStore(),\n  );\n  late final OwnerAlphaController _controller = OwnerAlphaController(\n",
)
replace(
    page,
    "    unawaited(_controller.initialize());\n",
    "    unawaited(_controller.initialize());\n    unawaited(_autoTradeController.initialize());\n",
)
replace(
    page,
    "    _controller.dispose();\n    super.dispose();",
    "    _controller.dispose();\n    _autoTradeController.dispose();\n    _autoTradeHttpClient.close();\n    super.dispose();",
)
replace(
    page,
    "            controller: _controller,\n            destination: _destination,",
    "            controller: _controller,\n            autoTradeController: _autoTradeController,\n            destination: _destination,",
)
replace(
    page,
    "const _destinations = [\n  _Destination(Icons.radar_outlined, Icons.radar_rounded),\n  _Destination(Icons.inbox_outlined, Icons.inbox_rounded),\n  _Destination(\n    Icons.candlestick_chart_outlined,\n    Icons.candlestick_chart_rounded,\n  ),\n  _Destination(Icons.view_list_outlined, Icons.view_list_rounded),\n  _Destination(Icons.science_outlined, Icons.science_rounded),\n  _Destination(Icons.person_outline_rounded, Icons.person_rounded),\n];\nconst _mobileDestinationIndexes = [0, 1, 2, 3, 5];",
    "const _destinations = [\n  _Destination(Icons.radar_outlined, Icons.radar_rounded),\n  _Destination(Icons.inbox_outlined, Icons.inbox_rounded),\n  _Destination(\n    Icons.candlestick_chart_outlined,\n    Icons.candlestick_chart_rounded,\n  ),\n  _Destination(Icons.view_list_outlined, Icons.view_list_rounded),\n  _Destination(Icons.science_outlined, Icons.science_rounded),\n  _Destination(Icons.smart_toy_outlined, Icons.smart_toy_rounded),\n  _Destination(Icons.person_outline_rounded, Icons.person_rounded),\n];\nconst _mobileDestinationIndexes = [0, 1, 2, 3, 5, 6];",
)
replace(
    page,
    "  4 => strings.strategyLab,\n  5 => strings.profile,",
    "  4 => strings.strategyLab,\n  5 => strings.isPersian ? 'ترید خودکار' : 'Auto Trade',\n  6 => strings.profile,",
)
replace(
    page,
    "    required this.controller,\n    required this.destination,",
    "    required this.controller,\n    required this.autoTradeController,\n    required this.destination,",
)
replace(
    page,
    "  final OwnerAlphaController controller;\n  final int destination;",
    "  final OwnerAlphaController controller;\n  final AutoTradeController autoTradeController;\n  final int destination;",
)
replace(
    page,
    "                   if (destination == 5)\n                     _ProfileView(\n                       controller: controller,\n                       themeMode: themeMode,\n                       locale: locale,\n                       onToggleTheme: onToggleTheme,\n                       onLocaleChanged: onLocaleChanged,\n                     )\n                   else if (controller.snapshot == null)",
    "                   if (destination == 6)\n                     _ProfileView(\n                       controller: controller,\n                       themeMode: themeMode,\n                       locale: locale,\n                       onToggleTheme: onToggleTheme,\n                       onLocaleChanged: onLocaleChanged,\n                     )\n                   else if (destination == 5)\n                     _AutoTradeView(\n                       controller: autoTradeController,\n                       analysisController: controller,\n                     )\n                   else if (controller.snapshot == null)",
)

pubspec = "src/client/quantara_app/pubspec.yaml"
replace(pubspec, "version: 0.11.2+14", "version: 0.12.0+15")
replace(
    pubspec,
    "  http: ^1.6.0\n",
    "  http: ^1.6.0\n  crypto: ^3.0.7\n  flutter_secure_storage: ^10.3.1\n",
)

build_gradle = "src/client/quantara_app/android/app/build.gradle.kts"
replace(build_gradle, "        minSdk = flutter.minSdkVersion", "        minSdk = 23")

workflow_path = Path(".github/workflows/flutter-ci.yml")
workflow_path.write_text(workflow_path.read_text().replace("0.11.2", "0.12.0"))

Path("src/client/quantara_app/test/bitunix_request_signer_test.dart").write_text(
    """import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_request_signer.dart';

void main() {
  test('matches the official two-stage Bitunix SHA-256 example', () {
    final result = BitunixRequestSigner.create(
      nonce: '123456',
      timestamp: '20241120123045',
      apiKey: 'yourApiKey',
      secretKey: 'yourSecretKey',
      query: const {'uid': '200', 'id': '1'},
      body: '{"uid":"2899","arr":[{"id":1,"name":"maple"},{"id":2,"name":"lily"}]}',
    );
    expect(
      result.digest,
      '75099831ac6803e9c5b79dd3cde2c3c529b4750bd3508186afdde0dd13599b38',
    );
    expect(
      result.sign,
      '00397cd1e52c7dce3258067324363b6361fabc9178a0912b330c138db8745655',
    );
  });
}
"""
)

Path("src/client/quantara_app/test/auto_trade_readonly_source_test.dart").write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Auto Trade is a separate read-only workspace', () {
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    final view = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    final client = File(
      'lib/features/auto_trade/data/bitunix_private_api_client.dart',
    ).readAsStringSync();
    expect(page, contains("part 'owner_alpha_auto_trade.dart';"));
    expect(page, contains("'ترید خودکار'"));
    expect(view, contains('نسخه 0.12A فقط خواندنی است'));
    expect(view, isNot(contains('place_order')));
    expect(client, contains('/api/v1/futures/account'));
    expect(client, contains('/get_pending_positions'));
    expect(client, contains('/get_pending_orders'));
    expect(client, isNot(contains('/trade/place_order')));
  });
}
"""
)

Path("docs/releases/v0.12.0-autotrade-readonly.md").write_text(
    """# Quantara 0.12.0 — Auto Trade read-only foundation

## Included

- a completely separate Auto Trade workspace;
- Android secure-storage onboarding for Bitunix API key and secret;
- official two-stage SHA-256 request signing;
- read-only USDT futures account, open-position and open-order sync;
- explicit Disconnected / Connecting / Read-only / Error states;
- masked key display, disconnect/revoke, and last-sync status;
- analysis watchlist preview without granting automatic trade permission;
- safety rollout roadmap for Shadow, Manual Approval, Canary, and Restricted Auto.

## Deliberately disabled

- order placement or cancellation;
- exchange leverage or margin-mode changes;
- TP/SL modification;
- autonomous live trading;
- withdrawal or transfer capabilities;
- web credential storage.

This release is a security and account-observability milestone, not a live-trading
release. Live execution remains blocked until the shadow and canary gates are
implemented and accepted.
"""
)

Path(".github/scripts/apply_autotrade_readonly_patch.py").unlink(missing_ok=True)
