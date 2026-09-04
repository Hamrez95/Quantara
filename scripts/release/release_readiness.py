#!/usr/bin/env python3
"""Deterministic release-readiness scoring for Quantara.

The score covers software/release-engineering evidence only. Physical-device,
exchange and production publication evidence are deliberately outside this score
and must never be inferred from it.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

WEIGHTS = {
    "repository_integrity": 20,
    "flutter_android_upgrade": 30,
    "windows_build": 15,
    "release_notes": 15,
    "rollback_plan": 10,
    "safety_regression": 10,
}
MINIMUM_SCORE = 90


def calculate_score(evidence: dict[str, bool]) -> int:
    unknown = set(evidence) - set(WEIGHTS)
    if unknown:
        raise ValueError(f"unknown readiness evidence: {', '.join(sorted(unknown))}")
    return sum(weight for key, weight in WEIGHTS.items() if evidence.get(key) is True)


def validate(evidence: dict[str, bool], minimum_score: int = MINIMUM_SCORE) -> int:
    missing = [key for key in WEIGHTS if evidence.get(key) is not True]
    score = calculate_score(evidence)
    if score < minimum_score:
        raise ValueError(
            f"release readiness score {score} is below required {minimum_score}; "
            f"missing evidence: {', '.join(missing) or 'none'}"
        )
    return score


def _load(path: Path) -> dict[str, bool]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("readiness evidence must be a JSON object")
    result: dict[str, bool] = {}
    for key, value in payload.items():
        if not isinstance(value, bool):
            raise ValueError(f"readiness evidence {key!r} must be boolean")
        result[str(key)] = value
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--minimum-score", type=int, default=MINIMUM_SCORE)
    args = parser.parse_args()
    score = validate(_load(args.evidence), args.minimum_score)
    print(f"quality_score={score}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
