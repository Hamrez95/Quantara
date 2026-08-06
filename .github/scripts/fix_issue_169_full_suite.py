from pathlib import Path

ROOT = Path('src/client/quantara_app')
TOOLS = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart'
ADAPTIVE_TEST = ROOT / 'test/adaptive_tp_source_test.dart'
V101_TEST = ROOT / 'test/local_live_v1_0_1_source_test.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)


tools = TOOLS.read_text(encoding='utf-8')
tools = replace_once(
    tools,
    """                          title: SelectableText(
                            event.type,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              SelectableText(event.message),
""",
    """                          title: SelectableText(
                            LocalLiveMessageLocalizer.localizeAudit(
                              kind: event.type,
                              message: event.message,
                              persian: _fa,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              SelectableText(
                                '${event.type}\\n${event.message}',
                                textDirection: TextDirection.ltr,
                              ),
""",
    'localized audit title with raw technical details',
)
TOOLS.write_text(tools, encoding='utf-8')

adaptive = ADAPTIVE_TEST.read_text(encoding='utf-8')
adaptive = replace_once(
    adaptive,
    """    final ui = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
""",
    """    final ui = File(
      'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
    ).readAsStringSync();
""",
    'adaptive audit UI source path',
)
ADAPTIVE_TEST.write_text(adaptive, encoding='utf-8')

v101 = V101_TEST.read_text(encoding='utf-8')
v101 = replace_once(
    v101,
    """      final ui = source(
        'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
      );
""",
    """      final ui = source(
        'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
      );
      final settingsUi = source(
        'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
      );
""",
    'settings part source',
)
v101 = replace_once(
    v101,
    "      expect(ui, contains(\"['5m', '15m', '1h', '4h']\"));\n",
    "      expect(settingsUi, contains(\"['5m', '15m', '1h', '4h']\"));\n",
    'timeframe source assertion',
)
V101_TEST.write_text(v101, encoding='utf-8')
