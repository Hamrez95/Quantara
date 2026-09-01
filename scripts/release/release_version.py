#!/usr/bin/env python3
"""Small, dependency-free SemVer helper used by local and GitHub releases."""
from __future__ import annotations

import argparse
import re
import sys

SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-(beta|rc)\.(0|[1-9]\d*))?$"
)
_STAGE_ORDER = {"beta": 0, "rc": 1, None: 2}


def parse(value: str) -> tuple[int, int, int, str | None, int | None]:
    match = SEMVER.fullmatch(value)
    if not match:
        raise ValueError(f"Invalid semantic version: {value}")
    major, minor, patch, stage, sequence = match.groups()
    return (
        int(major),
        int(minor),
        int(patch),
        stage,
        int(sequence) if sequence is not None else None,
    )


def version_key(value: str) -> tuple[int, int, int, int, int]:
    major, minor, patch, stage, sequence = parse(value)
    return major, minor, patch, _STAGE_ORDER[stage], sequence or 0


def newest_version(values: list[str]) -> str:
    if not values:
        raise ValueError("At least one semantic version is required.")
    return max(values, key=version_key)


def next_version(previous: str, release_type: str, channel: str) -> str:
    major, minor, patch, stage, sequence = parse(previous)

    if release_type == "promote":
        if channel != "stable":
            raise ValueError("Promotion is only valid for the stable channel.")
        if stage is None:
            raise ValueError("A stable version cannot be promoted again.")
        return f"{major}.{minor}.{patch}"

    if channel == "beta" and stage == "beta" and release_type == "patch":
        assert sequence is not None
        return f"{major}.{minor}.{patch}-beta.{sequence + 1}"

    if release_type == "major":
        major, minor, patch = major + 1, 0, 0
    elif release_type == "minor":
        minor, patch = minor + 1, 0
    elif release_type == "patch":
        patch += 1
    else:
        raise ValueError(f"Unsupported release type: {release_type}")

    suffix = "-beta.1" if channel == "beta" else ""
    return f"{major}.{minor}.{patch}{suffix}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--previous", required=True)
    parser.add_argument(
        "--published",
        action="append",
        default=[],
        help="Existing release or tag version that must be included in the version floor.",
    )
    parser.add_argument(
        "--release-type",
        choices=("promote", "patch", "minor", "major"),
        required=True,
    )
    parser.add_argument("--channel", choices=("beta", "stable"), required=True)
    parser.add_argument("--prefix", default="quantara-v")
    args = parser.parse_args()
    try:
        base_version = newest_version([args.previous, *args.published])
        version = next_version(base_version, args.release_type, args.channel)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    print(f"base_version={base_version}")
    print(f"version={version}")
    print(f"tag={args.prefix}{version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
