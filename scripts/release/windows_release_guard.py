#!/usr/bin/env python3
"""Fail-closed Windows release identity continuity checks."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

_SUPPORTED_ARCHITECTURES = {"x64"}
_WHITESPACE = re.compile(r"\s+")


def _normalized_signing_identity(value: str) -> str:
    normalized = _WHITESPACE.sub(" ", value.strip()).casefold()
    if not normalized:
        raise ValueError("Windows signing identity must not be empty.")
    return normalized


def _normalized_architecture(value: str) -> str:
    normalized = value.strip().lower()
    if normalized not in _SUPPORTED_ARCHITECTURES:
        raise ValueError("Windows release architecture is unsupported.")
    return normalized


def previous_windows_artifact(
    previous_manifest: dict[str, object],
) -> dict[str, object] | None:
    artifacts = previous_manifest.get("artifacts")
    if not isinstance(artifacts, dict):
        raise ValueError("Previous release manifest is missing artifacts.")

    windows = artifacts.get("windows")
    if windows is None:
        return None
    if not isinstance(windows, dict):
        raise ValueError("Previous release manifest has malformed Windows metadata.")
    return windows


def require_windows_identity_compatible(
    previous_manifest: dict[str, object],
    *,
    candidate_signing_identity: str,
    candidate_architecture: str,
    allow_first_windows_release: bool = False,
) -> None:
    windows = previous_windows_artifact(previous_manifest)
    if windows is None:
        if allow_first_windows_release:
            _normalized_signing_identity(candidate_signing_identity)
            _normalized_architecture(candidate_architecture)
            return
        raise ValueError(
            "Previous release manifest has no Windows metadata; "
            "first Windows publication must be explicitly acknowledged."
        )

    previous_signing_identity = windows.get("signingIdentity")
    previous_architecture = windows.get("architecture")
    if not isinstance(previous_signing_identity, str):
        raise ValueError("Previous release manifest has no Windows signing identity.")
    if not isinstance(previous_architecture, str):
        raise ValueError("Previous release manifest has no Windows architecture.")

    if _normalized_signing_identity(previous_signing_identity) != _normalized_signing_identity(
        candidate_signing_identity
    ):
        raise ValueError(
            "Candidate Windows signing identity does not match the previous published release."
        )
    if _normalized_architecture(previous_architecture) != _normalized_architecture(
        candidate_architecture
    ):
        raise ValueError(
            "Candidate Windows architecture does not match the previous published release."
        )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--previous-manifest", required=True)
    parser.add_argument("--windows-signing-identity", required=True)
    parser.add_argument("--windows-architecture", required=True)
    parser.add_argument("--allow-first-windows-release", action="store_true")
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        with Path(args.previous_manifest).open(encoding="utf-8") as handle:
            previous_manifest = json.load(handle)
        if not isinstance(previous_manifest, dict):
            raise ValueError("Previous release manifest root must be an object.")
        require_windows_identity_compatible(
            previous_manifest,
            candidate_signing_identity=args.windows_signing_identity,
            candidate_architecture=args.windows_architecture,
            allow_first_windows_release=args.allow_first_windows_release,
        )
        return 0
    except (json.JSONDecodeError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
