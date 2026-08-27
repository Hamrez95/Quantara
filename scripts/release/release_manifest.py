#!/usr/bin/env python3
"""Release integrity helpers for Quantara Android/PWA publication."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
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


def parse_revoked_builds(value: str, *, candidate_build: int) -> list[int]:
    """Parse an explicit emergency revocation list for forward recovery.

    Revocation never authorizes a downgrade. The newly published candidate must
    remain newer than every revoked build so affected installations recover by
    moving forward through the normal signed/checksummed update path.
    """

    raw = value.strip()
    if not raw:
        return []

    revoked: set[int] = set()
    for token in raw.split(","):
        normalized = token.strip()
        if not normalized or not normalized.isascii() or not normalized.isdigit():
            raise ValueError(
                "Revoked builds must be a comma-separated list of positive integers."
            )
        build = int(normalized)
        if build < 1:
            raise ValueError("Revoked build numbers must be positive.")
        if build >= candidate_build:
            raise ValueError(
                "A revoked build must be older than the forward-recovery candidate."
            )
        if build in revoked:
            raise ValueError("Revoked build numbers must be unique.")
        revoked.add(build)

    return sorted(revoked)


def _normalized_identity(value: str) -> str:
    normalized = value.strip().lower().replace(":", "")
    if not normalized:
        raise ValueError("Android signing identity must not be empty.")
    return normalized


def require_android_identity_compatible(
    previous_manifest: dict[str, object],
    *,
    candidate_package_id: str,
    candidate_signing_identity: str,
) -> None:
    artifacts = previous_manifest.get("artifacts")
    if not isinstance(artifacts, dict):
        raise ValueError("Previous release manifest is missing artifacts.")
    android = artifacts.get("android")
    if not isinstance(android, dict):
        raise ValueError("Previous release manifest is missing Android metadata.")

    previous_package_id = android.get("packageId")
    previous_signing_identity = android.get("signingIdentity")
    if not isinstance(previous_package_id, str) or not previous_package_id.strip():
        raise ValueError("Previous release manifest has no Android package identity.")
    if not isinstance(previous_signing_identity, str):
        raise ValueError("Previous release manifest has no Android signing identity.")

    candidate_package = candidate_package_id.strip()
    if not candidate_package:
        raise ValueError("Candidate Android package identity must not be empty.")
    if previous_package_id.strip() != candidate_package:
        raise ValueError(
            "Candidate Android package identity does not match the previous published release."
        )
    if _normalized_identity(previous_signing_identity) != _normalized_identity(
        candidate_signing_identity
    ):
        raise ValueError(
            "Candidate Android signing identity does not match the previous published release."
        )


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
    if args.rollout_percent < 0 or args.rollout_percent > 100:
        raise ValueError("Release rollout percentage must be between 0 and 100.")
    if not args.version.strip() or not args.minimum_supported_version.strip():
        raise ValueError("Release versions must not be empty.")
    if not args.android_package_id.strip() or not args.android_signing_identity.strip():
        raise ValueError("Android identity metadata is required.")

    revoked_builds = parse_revoked_builds(
        getattr(args, "revoked_builds", ""), candidate_build=args.build_number
    )

    return {
        "schemaVersion": 1,
        "channel": args.channel,
        "publishedAt": _published_at(args.published_at),
        "minimumSupportedVersion": args.minimum_supported_version.strip(),
        "mandatory": False,
        "releaseNotes": {"en": args.release_notes.strip()},
        "rolloutPercent": args.rollout_percent,
        "revokedBuilds": revoked_builds,
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

    identity_guard = subcommands.add_parser("guard-identity")
    identity_guard.add_argument("--previous-manifest", required=True)
    identity_guard.add_argument("--android-package-id", required=True)
    identity_guard.add_argument("--android-signing-identity", required=True)

    manifest = subcommands.add_parser("manifest")
    manifest.add_argument("--channel", choices=("stable", "canary"), required=True)
    manifest.add_argument("--version", required=True)
    manifest.add_argument("--build-number", type=int, required=True)
    manifest.add_argument("--published-at", required=True)
    manifest.add_argument("--minimum-supported-version", required=True)
    manifest.add_argument("--release-notes", default="")
    manifest.add_argument("--rollout-percent", type=int, default=100)
    manifest.add_argument("--revoked-builds", default="")
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

        if args.command == "guard-identity":
            with Path(args.previous_manifest).open(encoding="utf-8") as handle:
                previous_manifest = json.load(handle)
            if not isinstance(previous_manifest, dict):
                raise ValueError("Previous release manifest root must be an object.")
            require_android_identity_compatible(
                previous_manifest,
                candidate_package_id=args.android_package_id,
                candidate_signing_identity=args.android_signing_identity,
            )
            return 0

        payload = build_manifest(args)
        with open(args.output, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        return 0
    except (json.JSONDecodeError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
