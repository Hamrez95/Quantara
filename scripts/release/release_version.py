#!/usr/bin/env python3
"""Small, dependency-free SemVer helper used by local and GitHub releases."""
from __future__ import annotations

import argparse
import re
import sys

SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-beta\.(0|[1-9]\d*))?$")


def parse(value: str) -> tuple[int, int, int, int | None]:
    match = SEMVER.fullmatch(value)
    if not match:
        raise ValueError(f"Invalid semantic version: {value}")
    return tuple(int(part) if part is not None else None for part in match.groups())  # type: ignore[return-value]


def next_version(previous: str, release_type: str, channel: str) -> str:
    major, minor, patch, beta = parse(previous)
    if channel == "beta" and beta is not None and release_type == "patch":
        return f"{major}.{minor}.{patch}-beta.{beta + 1}"
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
    parser.add_argument("--release-type", choices=("patch", "minor", "major"), required=True)
    parser.add_argument("--channel", choices=("beta", "stable"), required=True)
    parser.add_argument("--prefix", default="quantara-v")
    args = parser.parse_args()
    try:
        version = next_version(args.previous, args.release_type, args.channel)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    print(f"version={version}")
    print(f"tag={args.prefix}{version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
