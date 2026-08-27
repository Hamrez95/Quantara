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

    def test_manifest_matches_runtime_schema_and_normalizes_integrity(self) -> None:
        args = argparse.Namespace(
            channel="stable",
            version="1.3.0",
            build_number=131,
            published_at="2026-08-27T06:00:00+00:00",
            minimum_supported_version="1.2.0",
            release_notes="Safer release integrity.",
            android_url="https://github.com/Hamrez95/Quantara/releases/download/quantara-v1.3.0/Quantara-1.3.0+131-android.apk",
            android_sha256="A" * 64,
            android_package_id="com.quantara.quantara_app",
            android_signing_identity="AA:BB:CC",
            pwa_url="https://github.com/Hamrez95/Quantara/releases/download/quantara-v1.3.0/Quantara-1.3.0-pwa.zip",
            pwa_sha256="B" * 64,
        )

        payload = release_manifest.build_manifest(args)

        self.assertEqual(payload["schemaVersion"], 1)
        self.assertEqual(payload["channel"], "stable")
        self.assertEqual(payload["publishedAt"], "2026-08-27T06:00:00Z")
        android = payload["artifacts"]["android"]
        self.assertEqual(android["buildNumber"], 131)
        self.assertEqual(android["sha256"], "a" * 64)
        self.assertEqual(android["packageId"], "com.quantara.quantara_app")
        self.assertEqual(android["signingIdentity"], "AA:BB:CC")

    def test_manifest_rejects_non_https_artifact(self) -> None:
        args = argparse.Namespace(
            channel="canary",
            version="1.3.0-beta.1",
            build_number=131,
            published_at="2026-08-27T06:00:00Z",
            minimum_supported_version="1.2.0",
            release_notes="",
            android_url="http://downloads.example/Quantara.apk",
            android_sha256="a" * 64,
            android_package_id="com.quantara.quantara_app",
            android_signing_identity="AA:BB:CC",
            pwa_url="https://downloads.example/Quantara-pwa.zip",
            pwa_sha256="b" * 64,
        )
        with self.assertRaisesRegex(ValueError, "trusted HTTPS"):
            release_manifest.build_manifest(args)


if __name__ == "__main__":
    unittest.main()
