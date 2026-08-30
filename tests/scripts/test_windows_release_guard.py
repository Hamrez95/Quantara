from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = (
    Path(__file__).parents[2] / "scripts" / "release" / "windows_release_guard.py"
)
SPEC = importlib.util.spec_from_file_location("windows_release_guard", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
windows_release_guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(windows_release_guard)


class WindowsReleaseGuardTests(unittest.TestCase):
    @staticmethod
    def _manifest(
        *,
        signing_identity: str = "CN=Quantara Software Publisher",
        architecture: str = "x64",
    ) -> dict[str, object]:
        return {
            "artifacts": {
                "windows": {
                    "signingIdentity": signing_identity,
                    "architecture": architecture,
                }
            }
        }

    def test_accepts_same_signer_and_architecture(self) -> None:
        windows_release_guard.require_windows_identity_compatible(
            self._manifest(),
            candidate_signing_identity="  cn=quantara   software publisher ",
            candidate_architecture="X64",
        )

    def test_rejects_signer_change(self) -> None:
        with self.assertRaisesRegex(ValueError, "signing identity"):
            windows_release_guard.require_windows_identity_compatible(
                self._manifest(),
                candidate_signing_identity="CN=Unexpected Publisher",
                candidate_architecture="x64",
            )

    def test_rejects_architecture_change(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported"):
            windows_release_guard.require_windows_identity_compatible(
                self._manifest(),
                candidate_signing_identity="CN=Quantara Software Publisher",
                candidate_architecture="arm64",
            )

    def test_rejects_missing_windows_metadata_by_default(self) -> None:
        with self.assertRaisesRegex(ValueError, "explicitly acknowledged"):
            windows_release_guard.require_windows_identity_compatible(
                {"artifacts": {}},
                candidate_signing_identity="CN=Quantara Software Publisher",
                candidate_architecture="x64",
            )

    def test_allows_explicit_first_windows_release_bootstrap(self) -> None:
        windows_release_guard.require_windows_identity_compatible(
            {"artifacts": {}},
            candidate_signing_identity="CN=Quantara Software Publisher",
            candidate_architecture="x64",
            allow_first_windows_release=True,
        )

    def test_first_release_bootstrap_still_validates_candidate(self) -> None:
        with self.assertRaises(ValueError):
            windows_release_guard.require_windows_identity_compatible(
                {"artifacts": {}},
                candidate_signing_identity=" ",
                candidate_architecture="x64",
                allow_first_windows_release=True,
            )

    def test_rejects_malformed_previous_windows_metadata(self) -> None:
        with self.assertRaisesRegex(ValueError, "malformed Windows metadata"):
            windows_release_guard.require_windows_identity_compatible(
                {"artifacts": {"windows": "invalid"}},
                candidate_signing_identity="CN=Quantara Software Publisher",
                candidate_architecture="x64",
            )


if __name__ == "__main__":
    unittest.main()
