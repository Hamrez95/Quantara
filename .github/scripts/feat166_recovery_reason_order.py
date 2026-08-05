from pathlib import Path

path = Path(
    'src/client/quantara_app/lib/features/auto_trade/application/'
    'local_live_orphan_recovery.dart'
)
text = path.read_text()
early = """    if (!pnl.isVerified) {
      return blocked('Position fill history is not exchange-verified.');
    }
"""
if early not in text:
    raise SystemExit('early verification block missing')
text = text.replace(early, '', 1)
anchor = """    if (explicitFills.any((fill) => fill.reduceOnly)) {
      return blocked(
        'A partially closed orphan position cannot be reconstructed safely.',
      );
    }
"""
if anchor not in text:
    raise SystemExit('partial-close anchor missing')
text = text.replace(
    anchor,
    anchor
    + """    if (!pnl.isVerified) {
      return blocked('Position fill history is not exchange-verified.');
    }
""",
    1,
)
path.write_text(text)
print('issue 166 recovery reason order corrected')
