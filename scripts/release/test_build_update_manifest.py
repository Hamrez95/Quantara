import argparse
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from build_update_manifest import build_manifest, main


class BuildUpdateManifestTests(unittest.TestCase):
    def _args(self, root: Path) -> argparse.Namespace:
        apk = root / "Quantara-1.3.0+130-android.apk"
        pwa = root / "Quantara-1.3.0-pwa.zip"
        apk.write_bytes(b"android-release")
        pwa.write_bytes(b"pwa-release")
        return argparse.Namespace(
            repository="Hamrez95/Quantara",
            tag="quantara-v1.3.0",
            channel="stable",
            version="1.3.0",
            build_number=130,
            minimum_supported_version="1.2.0",
            android_apk=str(apk),
            android_package_id="com.quantara.quantara_app",
            android_signing_identity="AA:BB:CC",
            pwa_archive=str(pwa),
            release_notes="Upgrade compatibility pending physical validation.",
            rollout_percent=100,
            mandatory=False,
            revoked_build=[126],
            published_at="2026-08-27T05:00:00Z",
            output=str(root / "release-manifest.json"),
        )

    def test_builds_immutable_https_artifact_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self._args(root)
            manifest = build_manifest(args)

            self.assertEqual(manifest["schemaVersion"], 1)
            self.assertEqual(manifest["channel"], "stable")
            self.assertEqual(manifest["revokedBuilds"], [126])
            android = manifest["artifacts"]["android"]
            self.assertEqual(android["packageId"], "com.quantara.quantara_app")
            self.assertEqual(android["signingIdentity"], "AA:BB:CC")
            self.assertEqual(
                android["url"],
                "https://github.com/Hamrez95/Quantara/releases/download/quantara-v1.3.0/Quantara-1.3.0+130-android.apk",
            )
            self.assertEqual(
                android["sha256"],
                hashlib.sha256(b"android-release").hexdigest(),
            )

    def test_missing_artifact_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self._args(root)
            Path(args.android_apk).unlink()
            with self.assertRaises(FileNotFoundError):
                build_manifest(args)

    def test_cli_writes_machine_readable_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = self._args(root)
            exit_code = main(
                [
                    "--repository",
                    args.repository,
                    "--tag",
                    args.tag,
                    "--channel",
                    args.channel,
                    "--version",
                    args.version,
                    "--build-number",
                    str(args.build_number),
                    "--minimum-supported-version",
                    args.minimum_supported_version,
                    "--android-apk",
                    args.android_apk,
                    "--android-package-id",
                    args.android_package_id,
                    "--android-signing-identity",
                    args.android_signing_identity,
                    "--pwa-archive",
                    args.pwa_archive,
                    "--published-at",
                    args.published_at,
                    "--output",
                    args.output,
                ]
            )
            self.assertEqual(exit_code, 0)
            payload = json.loads(Path(args.output).read_text(encoding="utf-8"))
            self.assertEqual(payload["channel"], "stable")
            self.assertEqual(payload["artifacts"]["pwa"]["buildNumber"], 130)


if __name__ == "__main__":
    unittest.main()
