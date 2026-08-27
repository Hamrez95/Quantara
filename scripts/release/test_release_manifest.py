#!/usr/bin/env python3

from __future__ import annotations

import argparse
import unittest

import release_manifest


class ReleaseManifestTests(unittest.TestCase):
    def _args(self, **overrides: object) -> argparse.Namespace:
        values: dict[str, object] = {
            "channel": "stable",
            "version": "1.2.3",
            "build_number": 123,
            "published_at": "2026-08-27T06:00:00Z",
            "minimum_supported_version": "1.2.2",
            "release_notes": "Safe upgrade metadata.",
            "android_url": "https://example.com/Quantara.apk",
            "android_sha256": "a" * 64,
            "android_package_id": "com.quantara.quantara_app",
            "android_signing_identity": "b" * 64,
            "android_min_sdk": 23,
            "android_target_sdk": 36,
            "android_abis": "x86_64,arm64-v8a,armeabi-v7a,arm64-v8a",
            "android_artifact_type": "universal-apk",
            "android_build_type": "release",
            "android_product_flavor": "production",
            "android_application_id_suffix": "",
            "pwa_url": "https://example.com/Quantara-pwa.zip",
            "pwa_sha256": "c" * 64,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_manifest_records_normalized_android_compatibility_metadata(self) -> None:
        manifest = release_manifest.build_manifest(self._args())

        android = manifest["artifacts"]["android"]  # type: ignore[index]
        self.assertEqual(android["minSdk"], 23)
        self.assertEqual(android["targetSdk"], 36)
        self.assertEqual(android["abis"], ["arm64-v8a", "armeabi-v7a", "x86_64"])
        self.assertEqual(android["artifactType"], "universal-apk")
        self.assertEqual(android["buildType"], "release")
        self.assertEqual(android["productFlavor"], "production")
        self.assertEqual(android["applicationIdSuffix"], "")

    def test_manifest_rejects_target_sdk_below_minimum(self) -> None:
        with self.assertRaisesRegex(ValueError, "SDK compatibility"):
            release_manifest.build_manifest(
                self._args(android_min_sdk=35, android_target_sdk=34)
            )

    def test_manifest_rejects_missing_or_malformed_abi_coverage(self) -> None:
        for value in ("", "arm64-v8a,../unsafe"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "ABI coverage"):
                    release_manifest.build_manifest(self._args(android_abis=value))


if __name__ == "__main__":
    unittest.main()
