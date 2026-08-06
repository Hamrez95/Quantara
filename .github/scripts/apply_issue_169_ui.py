from pathlib import Path
import re

ROOT = Path('src/client/quantara_app')
PAGE = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
AUTO = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
CONTROLLER = ROOT / 'lib/features/auto_trade/application/local_live_trade_controller.dart'
PUBSPEC = ROOT / 'pubspec.yaml'
DIAGNOSTIC_TEST = ROOT / 'test/local_live_diagnostic_bundle_test.dart'
UI_TEST = ROOT / 'test/local_live_issue_169_ui_source_test.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    next_text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    return next_text


# ---------------------------------------------------------------------------
# Library imports and part registration
# ---------------------------------------------------------------------------
page = PAGE.read_text(encoding='utf-8')
page = replace_once(
    page,
    "import 'dart:async';\nimport 'dart:math' as math;\n",
    """import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
""",
    'dart diagnostics imports',
)
page = replace_once(
    page,
    "import 'package:http/http.dart' as http;\n",
    """import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
""",
    'package diagnostics imports',
)
page = replace_once(
    page,
    "import '../../auto_trade/application/auto_trade_controller.dart';\n",
    """import '../../auto_trade/application/auto_trade_controller.dart';
import '../../auto_trade/application/local_live_diagnostic_bundle.dart';
import '../../auto_trade/application/local_live_trade_service.dart';
""",
    'local live diagnostics imports',
)
page = replace_once(
    page,
    "part 'owner_alpha_auto_trade.dart';\n",
    """part 'owner_alpha_auto_trade.dart';
part 'owner_alpha_local_live_tools.dart';
""",
    'local live tools part',
)
PAGE.write_text(page, encoding='utf-8')

# ---------------------------------------------------------------------------
# Dependency
# ---------------------------------------------------------------------------
pubspec = PUBSPEC.read_text(encoding='utf-8')
pubspec = replace_once(
    pubspec,
    '  http: ^1.6.0\n',
    '  http: ^1.6.0\n  share_plus: ^13.3.0\n',
    'share plus dependency',
)
PUBSPEC.write_text(pubspec, encoding='utf-8')

# ---------------------------------------------------------------------------
# Compact main card, strategy settings, timeframe view and detailed audit
# ---------------------------------------------------------------------------
auto = AUTO.read_text(encoding='utf-8')
auto = replace_once(
    auto,
    """  final Set<String> _enabledSymbols = {};
  final Set<String> _enabledTimeframes = {'1h', '4h'};
  int _leverage = 10;
""",
    """  final Set<String> _enabledSymbols = {};
  final Set<String> _enabledTimeframes = {'1h', '4h'};
  final Set<AnalysisStrategy> _enabledStrategies = {
    ...LocalLivePreferences.recommendedStrategies,
  };
  int _leverage = 10;
""",
    'strategy selection state',
)
auto = replace_once(
    auto,
    """        _enabledTimeframes
          ..clear()
          ..addAll(value.timeframes);
        _leverage = value.leverage;
""",
    """        _enabledTimeframes
          ..clear()
          ..addAll(value.timeframes);
        _enabledStrategies
          ..clear()
          ..addAll(value.strategies);
        _leverage = value.leverage;
""",
    'restore strategy selection',
)
auto = replace_once(
    auto,
    """    maximumConcurrentPositions: _maximumConcurrentPositions,
    targetAllocation: _targetAllocation,
""",
    """    maximumConcurrentPositions: _maximumConcurrentPositions,
    strategies: _enabledStrategies.toList(growable: false),
    targetAllocation: _targetAllocation,
""",
    'persist strategy selection',
)
auto = auto.replace(
    'هر ورود همچنان باید با SL کامل و سه TP تأییدشده صرافی محافظت شود.',
    'هر ورود همچنان باید با SL کامل و پوشش کامل حجم توسط هدف‌های فعال تأییدشده صرافی محافظت شود.',
    1,
)
auto = auto.replace(
    'every entry still requires a full exchange-confirmed stop and three targets.',
    'every entry still requires a full exchange-confirmed stop and complete coverage by active targets.',
    1,
)

settings_pattern = (
    r"          const Divider\(height: 28\),\n"
    r"          if \(!_preferencesLoaded\) \.\.\.\[.*?"
    r"          const SizedBox\(height: 14\),\n"
    r"          Row\(\n"
    r"            children: \["
)
settings_replacement = """          const Divider(height: 28),
          if (!_preferencesLoaded) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          _buildLocalLiveConfigurationSummary(serviceActive: serviceActive),
          if (status.managedPositions.isNotEmpty ||
              exchangeOpenPositions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildManagedPositionTimeframes(
              status: status,
              exchangePositions: exchangeOpenPositions,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: ["""
auto = regex_once(
    auto,
    settings_pattern,
    settings_replacement,
    'replace inline settings with gear summary',
)

auto = replace_once(
    auto,
    """    if (!recoveryOnly &&
        (_enabledSymbols.isEmpty || _enabledTimeframes.isEmpty)) {
""",
    """    if (!recoveryOnly &&
        (_enabledSymbols.isEmpty ||
            _enabledTimeframes.isEmpty ||
            _enabledStrategies.isEmpty)) {
""",
    'start strategy validation',
)
auto = auto.replace(
    'حداقل یک نماد و یک تایم‌فریم انتخاب کن.',
    'حداقل یک نماد، یک تایم‌فریم و یک استراتژی انتخاب کن.',
    1,
)
auto = auto.replace(
    'Select at least one symbol and timeframe.',
    'Select at least one symbol, timeframe and strategy.',
    1,
)
auto = replace_once(
    auto,
    """              Text('${_t('اهرم', 'Leverage')}: ${_leverage}x'),
""",
    """              Text(
                '${_t('استراتژی‌ها', 'Strategies')}: ${_enabledStrategies.map(_strategyTitle).join(' · ')}',
              ),
              Text('${_t('اهرم', 'Leverage')}: ${_leverage}x'),
""",
    'start confirmation strategy summary',
)
auto = replace_once(
    auto,
    """        strategy: widget.analysisController.strategy,
        cadence: widget.analysisController.cadence,
""",
    """        strategy: _enabledStrategies.first,
        strategies: _enabledStrategies.toList(growable: false),
        cadence: widget.analysisController.cadence,
""",
    'start multi-strategy configuration',
)
auto = regex_once(
    auto,
    r"  Future<void> _showAudit\(\) async \{.*?\n  \}\n\n  String _stateLabel",
    """  Future<void> _showAudit() => _showDetailedLocalLiveAudit();

  String _stateLabel""",
    'replace generic audit sheet',
)
AUTO.write_text(auto, encoding='utf-8')

# ---------------------------------------------------------------------------
# Preserve timeframe summaries through controller-created status copies
# ---------------------------------------------------------------------------
controller = CONTROLLER.read_text(encoding='utf-8')
needle = '        managedPositionCount: _status.managedPositionCount,\n'
if controller.count(needle) < 2:
    raise RuntimeError(
        f'controller managed count copies: expected at least two, found {controller.count(needle)}'
    )
controller = controller.replace(
    needle,
    needle + '        managedPositions: _status.managedPositions,\n',
)
CONTROLLER.write_text(controller, encoding='utf-8')

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
DIAGNOSTIC_TEST.write_text(r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_diagnostic_bundle.dart';

void main() {
  test('diagnostic bundle recursively strips credentials and secret values', () {
    const explicitSecret = 'super-secret-value';
    final encoded = LocalLiveDiagnosticBundle.encode(
      generatedAt: DateTime.utc(2026, 8, 6),
      explicitSecretValues: const [explicitSecret],
      sections: const {
        'configuration': {
          'apiKey': 'key-value',
          'secretKey': explicitSecret,
          'nested': {
            'Authorization': 'Bearer token-value',
            'safe': 'BTCUSDT',
          },
        },
        'audit': [
          'authorization=Basic dXNlcjpwYXNz',
          'API key: visible-key',
          'normal event',
        ],
      },
    );

    expect(encoded, isNot(contains('key-value')));
    expect(encoded, isNot(contains(explicitSecret)));
    expect(encoded, isNot(contains('token-value')));
    expect(encoded, isNot(contains('visible-key')));
    expect(encoded, isNot(contains('dXNlcjpwYXNz')));
    expect(encoded, isNot(contains('secretKey')));
    expect(encoded, contains('BTCUSDT'));
    expect(encoded, contains('normal event'));
  });

  test('diagnostic output remains valid structured JSON', () {
    final encoded = LocalLiveDiagnosticBundle.encode(
      generatedAt: DateTime.utc(2026, 8, 6),
      sections: const {
        'status': {'state': 'running', 'managedPositionCount': 2},
      },
    );
    final decoded = jsonDecode(encoded) as Map<String, Object?>;
    expect(decoded['schemaVersion'], LocalLiveDiagnosticBundle.schemaVersion);
    expect(decoded['scope'], 'local-live-support');
    expect(decoded['sections'], isA<Map<String, Object?>>());
  });
}
''', encoding='utf-8')

UI_TEST.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Local Live main card delegates configuration to a gear sheet', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    expect(source, contains('_buildLocalLiveConfigurationSummary'));
    expect(source, contains('_showLocalLiveSettings'));
    expect(source, isNot(contains("_t('نمادهای مجاز', 'Allowed symbols')")));
    expect(source, contains('_enabledStrategies'));
    expect(source, contains('strategies: _enabledStrategies.toList'));
  });

  test('settings sheet exposes strategies and diagnostic export', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
    ).readAsStringSync();
    expect(source, contains('Icons.settings_rounded'));
    expect(source, contains('CheckboxListTile'));
    expect(source, contains('for (final strategy in AnalysisStrategy.values)'));
    expect(source, contains('LocalLivePreferences.recommendedStrategies'));
    expect(source, contains('SharePlus.instance.share'));
    expect(source, contains('LocalLiveDiagnosticBundle.encode'));
    expect(source, contains('managed.timeframe'));
    expect(source, contains('Unknown timeframe'));
  });

  test('support export is user initiated and never reads secure credentials', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
    ).readAsStringSync();
    expect(source, contains("label: Text(_t('خروجی JSON', 'Export JSON'))"));
    expect(source, isNot(contains('SecureAutoTradeCredentialsStore')));
    expect(source, isNot(contains("getData<String>(key: 'api")));
  });
}
''', encoding='utf-8')
