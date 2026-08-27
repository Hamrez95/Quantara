#!/usr/bin/env python3
"""Build a schema-v1 Quantara update manifest from immutable release artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("value must be >= 1")
    return parsed


def _rollout(value: str) -> int:
    parsed = int(value)
    if parsed < 0 or parsed > 100:
        raise argparse.ArgumentTypeError("rollout must be between 0 and 100")
    return parsed


def build_manifest(args: argparse.Namespace) -> dict[str, object]:
    if args.channel not in {"stable", "canary", "internal"}:
        raise ValueError("unsupported release channel")
    if not args.version.strip() or not args.minimum_supported_version.strip():
        raise ValueError("version metadata must not be empty")

    release_base = (
        f"https://github.com/{args.repository}/releases/download/{args.tag}"
    )
    android_path = Path(args.android_apk)
    pwa_path = Path(args.pwa_archive)
    if not android_path.is_file() or not pwa_path.is_file():
        raise FileNotFoundError("release artifact is missing")

    signer = args.android_signing_identity.strip()
    if not signer:
        raise ValueError("Android signing identity is required")

    notes = args.release_notes.strip() or f"Quantara {args.version}"
    return {
        "schemaVersion": 1,
        "channel": args.channel,
        "publishedAt": args.published_at,
        "minimumSupportedVersion": args.minimum_supported_version.strip(),
        "mandatory": args.mandatory,
        "releaseNotes": {"en": notes},
        "rolloutPercent": args.rollout_percent,
        "revokedBuilds": args.revoked_build,
        "artifacts": {
            "android": {
                "version": args.version.strip(),
                "buildNumber": args.build_number,
                "url": f"{release_base}/{android_path.name}",
                "sha256": _sha256(android_path),
                "packageId": args.android_package_id.strip(),
                "signingIdentity": signer,
                "architecture": "universal",
            },
            "pwa": {
                "version": args.version.strip(),
                "buildNumber": args.build_number,
                "url": f"{release_base}/{pwa_path.name}",
                "sha256": _sha256(pwa_path),
            },
        },
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--channel", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", type=_positive_int, required=True)
    parser.add_argument("--minimum-supported-version", required=True)
    parser.add_argument("--android-apk", required=True)
    parser.add_argument("--android-package-id", required=True)
    parser.add_argument("--android-signing-identity", required=True)
    parser.add_argument("--pwa-archive", required=True)
    parser.add_argument("--release-notes", default="")
    parser.add_argument("--rollout-percent", type=_rollout, default=100)
    parser.add_argument("--mandatory", action="store_true")
    parser.add_argument(
        "--revoked-build", type=_positive_int, action="append", default=[]
    )
    parser.add_argument(
        "--published-at",
        default=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    )
    parser.add_argument("--output", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    manifest = build_manifest(args)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
