from pathlib import Path

path = Path('src/client/quantara_app/test/local_live_issue_169_ui_source_test.dart')
text = path.read_text(encoding='utf-8')

old_main = """    expect(source, contains('_buildLocalLiveConfigurationSummary'));
    expect(source, contains('_showLocalLiveSettings'));
    expect(source, isNot(contains("_t('نمادهای مجاز', 'Allowed symbols')")));
"""
new_main = """    expect(source, contains('_buildLocalLiveConfigurationSummary'));
    expect(source, isNot(contains("_t('نمادهای مجاز', 'Allowed symbols')")));
"""
if text.count(old_main) != 1:
    raise RuntimeError(f'expected one main-card assertion block, found {text.count(old_main)}')
text = text.replace(old_main, new_main, 1)

old_tools = """    expect(source, contains('Icons.settings_rounded'));
    expect(source, contains('CheckboxListTile'));
    expect(source, contains('for (final strategy in AnalysisStrategy.values)'));
    expect(source, contains('LocalLivePreferences.recommendedStrategies'));
"""
new_tools = """    expect(source, contains('Icons.settings_rounded'));
    expect(source, contains('_showLocalLiveSettings'));
    expect(source, contains('CheckboxListTile'));
    expect(source, contains('for (final strategy in AnalysisStrategy.values)'));
    expect(source, contains('.recommendedStrategies'));
"""
if text.count(old_tools) != 1:
    raise RuntimeError(f'expected one tools assertion block, found {text.count(old_tools)}')
text = text.replace(old_tools, new_tools, 1)

path.write_text(text, encoding='utf-8')
