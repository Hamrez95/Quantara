from __future__ import annotations

import argparse
import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[2] / "scripts" / "release" / "release_manifest.py"
SPEC = importlib.util.spec_from_file_location("release_manifest", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
release_manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_manifest)


class ReleaseManifestTests(unittest.TestCase):
    def test_build_guard_reads_current_and_legacy_android_asset_names(self) -> None:
        names = [
            "Quantara-1.3.0+130-android.apk",
            "Quantara-1.2.0-rc.2-build124-EPHEMERAL-QA.apk",
            "Quantara-1.3.0-pwa.zip",
        ]
        self.assertEqual(release_manifest.require_monotonic_build(131, names), 130)

    def test_build_guard_rejects_equal_or_lower_candidate(self) -> None:
        names = ["Quantara-1.3.0+130-android.apk"]
        with self.assertRaisesRegex(ValueError, "greater than published build 130"):
            release_manifest.require_monotonic_build(130, names)

    def test_android_identity_guard_accepts_same_package_and_signer(self) -> None:
        previous = {
            "artifacts": {
                "android": {
                    "packageId": "com.quantara.quantara_app",
                    "signingIdentity": "AA:BB:CC",
                }
            }
        }
        release_manifest.require_android_identity_compatible(
            previous,
            candidate_package_id="com.quantara.quantara_app",
            candidate_signing_identity="aabbcc",
        )

    def test_android_identity_guard_rejects_package_change(self) -> None:
        previous = {
            "artifacts": {
                "android": {
                    "packageId": "com.quantara.quantara_app",
                    "signingIdentity": "AA:BB:CC",
                }
            }
        }
        with self.assertRaisesRegex(ValueError, "package identity"):
            release_manifest.require_android_identity_compatible(
                previous,
                candidate_package_id="com.quantara.other",
                candidate_signing_identity="AA:BB:CC",
            )

    def test_android_identity_guard_rejects_signer_change(self) -> None:
        previous = {
            "artifacts": {
                "android": {
                    "packageId": "com.quantara.quantara_app",
                    "signingIdentity": "AA:BB:CC",
                }
            }
        }
        with self.assertRaisesRegex(ValueError, "signing identity"):
            release_manifest.require_android_identity_compatible(
                previous,
                candidate_package_id="com.quantara.quantara_app",
                candidate_signing_identity="DD:EE:FF",
            )

    def test_android_identity_guard_rejects_incomplete_previous_manifest(self) -> None:
        with self.assertRaisesRegex(ValueError, "Android metadata"):
            release_manifest.require_android_identity_compatible(
                {"artifacts": {}},
                candidate_package_id="com.quantara.quantara_app",
                candidate_signing_identity="AA:BB:CC",
            )

    def test_revoked_builds_are_normalized_for_forward_recovery(self) -> None:
        self.assertEqual(
            release_manifest.parse_revoked_builds("129, 127,128", candidate_build=131),
            [127, 128, 129],
        )
        self.assertEqual(
            release_manifest.parse_revoked_builds("", candidate_build=131), []
        )

    def test_revoked_builds_reject_ambiguous_or_non_forward_recovery(self) -> None:
        invalid = ("0", "129,129", "abc", "129,,130", "131", "132")
        for value in invalid:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    release_manifest.parse_revoked_builds(value, candidate_build=131)

    @staticmethod
    def _manifest_args(
        *, rollout_percent: int = 100, revoked_builds: str = ""
    ) -> argparse.Namespace:
        return argparse.Namespace(
            channel="stable",
            version="1.3.0",
            build_number=131,
            published_at="2026-08-27T06:00:00+00:00",
            minimum_supported_version="1.2.0",
            release_notes="Safer release integrity.",
            rollout_percent=rollout_percent,
            revoked_builds=revoked_builds,
            android_url="https://github.com/Hamrez95/Quantara/releases/download/quantara-v1.3.0/Quantara-1.3.0+131-android.apk",
            android_sha256="A" * 64,
            android_package_id="com.quantara.quantara_app",
            android_signing_identity="AA:BB:CC",
            windows_url="",
            windows_sha256="",
            windows_signing_identity="",
            windows_architecture="",
            pwa_url="https://github.com/Hamrez95/Quantara/releases/download/quantara-v1.3.0/Quantara-1.3.0-pwa.zip",
            pwa_sha256="B" * 64,
        )

    def test_manifest_matches_runtime_schema_and_normalizes_integrity(self) -> None:
        payload = release_manifest.build_manifest(
            self._manifest_args(rollout_percent=25, revoked_builds="129,127")
        )

        self.assertEqual(payload["schemaVersion"], 1)
        self.assertEqual(payload["channel"], "stable")
        self.assertEqual(payload["publishedAt"], "2026-08-27T06:00:00Z")
        self.assertEqual(payload["rolloutPercent"], 25)
        self.assertEqual(payload["revokedBuilds"], [127, 129])
        self.assertNotIn("windows", payload["artifacts"])
        android = payload["artifacts"]["android"]
        self.assertEqual(android["buildNumber"], 131)
        self.assertEqual(android["sha256"], "a" * 64)
        self.assertEqual(android["packageId"], "com.quantara.quantara_app")
        self.assertEqual(android["signingIdentity"], "AA:BB:CC")

    def test_manifest_emits_complete_verified_windows_artifact(self) -> None:
        args = self._manifest_args()
        args.windows_url = (
            "https://github.com/Hamrez95/Quantara/releases/download/"
            "quantara-v1.3.0/QuantaraSetup-1.3.0+131-x64.exe"
        )
        args.windows_sha256 = "C" * 64
        args.windows_signing_identity = "Quantara Software Publisher"
        args.windows_architecture = "X64"

        payload = release_manifest.build_manifest(args)
        windows = payload["artifacts"]["windows"]
        self.assertEqual(windows["version"], "1.3.0")
        self.assertEqual(windows["buildNumber"], 131)
        self.assertEqual(windows["sha256"], "c" * 64)
        self.assertEqual(windows["signingIdentity"], "Quantara Software Publisher")
        self.assertEqual(windows["architecture"], "x64")

    def test_manifest_rejects_partial_windows_metadata(self) -> None:
        args = self._manifest_args()
        args.windows_url = "https://downloads.example/QuantaraSetup.exe"
        with self.assertRaisesRegex(ValueError, "must include URL"):
            release_manifest.build_manifest(args)

    def test_manifest_rejects_untrusted_windows_metadata(self) -> None:
        invalid_cases = (
            {"windows_url": "http://downloads.example/QuantaraSetup.exe"},
            {"windows_sha256": "not-a-hash"},
            {"windows_architecture": "arm64"},
        )
        for overrides in invalid_cases:
            with self.subTest(overrides=overrides):
                args = self._manifest_args()
                args.windows_url = "https://downloads.example/QuantaraSetup.exe"
                args.windows_sha256 = "C" * 64
                args.windows_signing_identity = "Quantara Software Publisher"
                args.windows_architecture = "x64"
                for key, value in overrides.items():
                    setattr(args, key, value)
                with self.assertRaises(ValueError):
                    release_manifest.build_manifest(args)

    def test_manifest_rejects_rollout_outside_percentage_bounds(self) -> None:
        for invalid in (-1, 101):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(ValueError, "between 0 and 100"):
                    release_manifest.build_manifest(
                        self._manifest_args(rollout_percent=invalid)
                    )

    def test_manifest_rejects_non_https_artifact(self) -> None:
        args = self._manifest_args()
        args.channel = "canary"
        args.version = "1.3.0-beta.1"
        args.android_url = "http://downloads.example/Quantara.apk"
        args.pwa_url = "https://downloads.example/Quantara-pwa.zip"
        with self.assertRaisesRegex(ValueError, "trusted HTTPS"):
            release_manifest.build_manifest(args)


if __name__ == "__main__":
    unittest.main()
