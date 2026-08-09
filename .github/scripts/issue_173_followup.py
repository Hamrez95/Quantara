from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected exactly one match in {path}, found {count}: {old[:120]!r}"
        )
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


# Bitunix has emitted both gross-like and net-like realizedPNL semantics for open
# positions across historical/private payloads. Accept either representation, but
# keep fee and funding cross-checks strict. This preserves old verified recovery
# fixtures while matching the physical AAVE payload where realizedPNL is net.
replace_once(
    "src/client/quantara_app/lib/features/auto_trade/domain/trading_pnl_projection.dart",
    """      final pendingRealizedMismatch =
          open?.realizedPnl != null &&
          pendingNetFromHistory != null &&
          (pendingNetFromHistory - open!.realizedPnl!).abs() > tolerance;
""",
    """      final pendingRealizedMatchesGross =
          fillsAvailable &&
          open?.realizedPnl != null &&
          realizedValue != null &&
          (realizedValue - open!.realizedPnl!).abs() <= tolerance;
      final pendingRealizedMatchesNet =
          open?.realizedPnl != null &&
          pendingNetFromHistory != null &&
          (pendingNetFromHistory - open!.realizedPnl!).abs() <= tolerance;
      final pendingRealizedMismatch =
          open?.realizedPnl != null &&
          !pendingRealizedMatchesGross &&
          !pendingRealizedMatchesNet;
""",
)

# RC2 remains the release line; this physical QA patch advances only the Android
# build number. Keep the source lock test aligned with the testable artifact.
replace_once(
    "src/client/quantara_app/test/release_1_2_0_rc_2_source_test.dart",
    "version: 1.2.0-rc.2+121",
    "version: 1.2.0-rc.2+123",
)

print("Issue #173 compatibility follow-up staged successfully.")
