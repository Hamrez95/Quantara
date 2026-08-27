#!/usr/bin/env python3
"""Release integrity helpers for Quantara Android/PWA publication."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

_SHA256 = re.compile(r"^[a-fA-F0-9]{64}$")
_ANDROID_ASSET_PATTERNS = (
    re.compile(r"^Quantara-.+\+(\d+)-android\.apk$"),
    re.compile(r"^Quantara-.+-build(\d+)-[^/]*\.apk$"),
)


def published_android_builds(asset_names: list[str]) -> list[int]:
    builds: list[int] = []
    for raw_name in asset_names:
        name = raw_name.strip()
        for pattern in _ANDROID_ASSET_PATTERNS:
            match = pattern.match(name)
            if match:
                builds.append(int(match.group(1)))
                break
    return builds


def require_monotonic_build(candidate: int, asset_names: list[str]) -> int:
    if candidate < 1:
        raise ValueError("Candidate Android build number must be positive.")
    previous = max(published_android_builds(asset_names), default=0)
    if candidate <= previous:
        raise ValueError(
            f"Candidate Android build {candidate} must be greater than "
            f"published build {previous}."
        )
    return previous


def _https_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError("Release artifact URLs must use trusted HTTPS origins.")
    return value


def _sha256(value: str) -> str:
    normalized = value.strip().lower()
    if not _SHA256.fullmatch(normalized):
        raise ValueError("Release artifact SHA-256 is invalid.")
    return normalized


def _published_at(value: str) -> str:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Manifest publication time must include a timezone.")
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def build_manifest(args: argparse.Namespace) -> dict[str, object]:
    if args.build_number < 1:
        raise ValueError("Release build number must be positive.")
    if not args.version.strip() or not args.minimum_supported_version.strip():
        raise ValueError("Release versions must not be empty.")
    if not args.android_package_id.strip() or not args.android_signing_identity.strip():
        raise ValueError("Android identity metadata is required.")

    return {
        "schemaVersion": 1,
        "channel": args.channel,
        "publishedAt": _published_at(args.published_at),
        "minimumSupportedVersion": args.minimum_supported_version.strip(),
        "mandatory": False,
        "releaseNotes": {"en": args.release_notes.strip()},
        "rolloutPercent": 100,
        "revokedBuilds": [],
        "artifacts": {
            "android": {
                "version": args.version.strip(),
                "buildNumber": args.build_number,
                "url": _https_url(args.android_url),
                "sha256": _sha256(args.android_sha256),
                "packageId": args.android_package_id.strip(),
                "signingIdentity": args.android_signing_identity.strip(),
            },
            "pwa": {
                "version": args.version.strip(),
                "buildNumber": args.build_number,
                "url": _https_url(args.pwa_url),
                "sha256": _sha256(args.pwa_sha256),
            },
        },
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subcommands = parser.add_subparsers(dest="command", required=True)

    guard = subcommands.add_parser("guard-build")
    guard.add_argument("--candidate", type=int, required=True)

    manifest = subcommands.add_parser("manifest")
    manifest.add_argument("--channel", choices=("stable", "canary"), required=True)
    manifest.add_argument("--version", required=True)
    manifest.add_argument("--build-number", type=int, required=True)
    manifest.add_argument("--published-at", required=True)
    manifest.add_argument("--minimum-supported-version", required=True)
    manifest.add_argument("--release-notes", default="")
    manifest.add_argument("--android-url", required=True)
    manifest.add_argument("--android-sha256", required=True)
    manifest.add_argument("--android-package-id", required=True)
    manifest.add_argument("--android-signing-identity", required=True)
    manifest.add_argument("--pwa-url", required=True)
    manifest.add_argument("--pwa-sha256", required=True)
    manifest.add_argument("--output", required=True)
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        if args.command == "guard-build":
            previous = require_monotonic_build(
                args.candidate,
                [line for line in sys.stdin.read().splitlines() if line.strip()],
            )
            print(f"previous_build={previous}")
            return 0

        payload = build_manifest(args)
        with open(args.output, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        return 0
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
