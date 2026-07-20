from pathlib import Path

path = Path('tests/backend/Quantara.Domain.Tests/ResearchSourceRegistryLoaderTests.cs')
text = path.read_text(encoding='utf-8')
old = '    private const string PublisherProperty =\n        "              \\\"publisher\\\": \\\"Trade City Pro\\\",\\n";'
new = '    private const string PublisherProperty =\n        "\\\"publisher\\\": \\\"Trade City Pro\\\",";'
if old not in text:
    raise SystemExit('expected PublisherProperty fixture not found')
text = text.replace(old, new, 1)
old_insert = 'PublisherProperty + "              \\\"unreviewed_override\\\": true,\\n"'
new_insert = 'PublisherProperty + "\\n      \\\"unreviewed_override\\\": true,"'
if old_insert not in text:
    raise SystemExit('expected unknown-property fixture not found')
text = text.replace(old_insert, new_insert, 1)
path.write_text(text, encoding='utf-8')
