from pathlib import Path

path = Path('src/client/quantara_app/test/issue_172_private_sync_cache_test.dart')
text = path.read_text()
text = text.replace(
    "    expect(first.pnlProjection.isVerified, isTrue);\n    expect(first.pnlProjection.positions, hasLength(101));\n",
    "    expect(first.pnlProjection, isNotNull);\n    expect(first.pnlProjection!.isVerified, isTrue);\n    expect(first.pnlProjection!.positions, hasLength(101));\n",
    1,
)
text = text.replace(
    "    expect(second.pnlProjection.isVerified, isTrue);\n    expect(second.pnlProjection.positions, hasLength(101));\n",
    "    expect(second.pnlProjection, isNotNull);\n    expect(second.pnlProjection!.isVerified, isTrue);\n    expect(second.pnlProjection!.positions, hasLength(101));\n",
    1,
)
path.write_text(text)
print('Issue #172 nullable test assertions fixed.')
