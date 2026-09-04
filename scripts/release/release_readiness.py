#!/usr/bin/env python3
"""Fail-closed release-readiness scoring and manifest validation for Quantara.

The score covers software/release-engineering evidence only. Physical-device,
exchange, profitability, permanent-signing and publication evidence are explicit
manual gates and must never be inferred from CI.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

WEIGHTS = {
    "repository_integrity": 15,
    "flutter_android_upgrade": 25,
    "windows_build": 15,
    "installable_artifact_smoke": 10,
    "stability_report": 10,
    "release_notes": 10,
    "rollback_plan": 10,
    "safety_regression": 5,
}
MANDATORY = frozenset(WEIGHTS)
MINIMUM_SCORE = 90
_SHA = re.compile(r"^[0-9a-f]{40}$")
_VERSION = re.compile(r"^version:\s*([^+\s]+)\+([0-9]+)\s*$")
MANUAL_GATE_STATUSES = {
    "physical_device_permanent_signing": "pending",
    "production_store_publication": "approval_required",
}


def calculate_score(evidence: dict[str, bool]) -> int:
    unknown = set(evidence) - set(WEIGHTS)
    if unknown:
        raise ValueError(f"unknown readiness evidence: {', '.join(sorted(unknown))}")
    return sum(weight for key, weight in WEIGHTS.items() if evidence.get(key) is True)


def validate(evidence: dict[str, bool], minimum_score: int = MINIMUM_SCORE) -> int:
    missing_mandatory = sorted(key for key in MANDATORY if evidence.get(key) is not True)
    if missing_mandatory:
        raise ValueError(
            "mandatory release evidence is missing: " + ", ".join(missing_mandatory)
        )
    score = calculate_score(evidence)
    if score < minimum_score:
        missing = [key for key in WEIGHTS if evidence.get(key) is not True]
        raise ValueError(
            f"release readiness score {score} is below required {minimum_score}; "
            f"missing evidence: {', '.join(missing) or 'none'}"
        )
    return score


def _object(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be a JSON object")
    return value


def _load(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return _object(payload, "readiness evidence")


def _pubspec_version(root: Path) -> tuple[str, int]:
    pubspec = root / "src/client/quantara_app/pubspec.yaml"
    for raw_line in pubspec.read_text(encoding="utf-8").splitlines():
        match = _VERSION.match(raw_line.strip())
        if match:
            return match.group(1), int(match.group(2))
    raise ValueError("pubspec.yaml has no parseable version/build number")


def _manifest_evidence(payload: dict[str, Any], root: Path) -> dict[str, bool]:
    records = _object(payload.get("evidence"), "manifest evidence")
    unknown = set(records) - set(WEIGHTS)
    if unknown:
        raise ValueError(f"unknown readiness evidence: {', '.join(sorted(unknown))}")

    evidence: dict[str, bool] = {}
    for key in WEIGHTS:
        record = _object(records.get(key), f"evidence.{key}")
        passed = record.get("passed")
        if not isinstance(passed, bool):
            raise ValueError(f"readiness evidence {key!r} passed must be boolean")
        evidence[key] = passed

        path_value = record.get("path")
        if path_value is not None:
            if not isinstance(path_value, str) or not path_value.strip():
                raise ValueError(f"evidence.{key}.path must be a non-empty path")
            if not (root / path_value).is_file():
                raise ValueError(f"evidence.{key} path does not exist: {path_value}")

        if key not in {"stability_report", "release_notes", "rollback_plan"}:
            reference_fields = ("runId", "jobIds", "checkRunIds", "artifactIds")
            if not any(field in record for field in reference_fields):
                raise ValueError(f"evidence.{key} has no auditable CI/artifact reference")

    return evidence


def validate_manifest(
    payload: dict[str, Any],
    *,
    root: Path,
    minimum_score: int = MINIMUM_SCORE,
    expected_software_candidate_sha: str | None = None,
) -> int:
    if payload.get("schemaVersion") != 1:
        raise ValueError("unsupported readiness manifest schemaVersion")

    candidate_sha = payload.get("softwareCandidateSha")
    if not isinstance(candidate_sha, str) or not _SHA.fullmatch(candidate_sha):
        raise ValueError("softwareCandidateSha must be a lowercase 40-character SHA")
    if expected_software_candidate_sha is not None:
        expected = expected_software_candidate_sha.strip().lower()
        if candidate_sha != expected:
            raise ValueError(
                f"stale softwareCandidateSha: manifest={candidate_sha} expected={expected}"
            )

    version = payload.get("version")
    build_number = payload.get("buildNumber")
    if not isinstance(version, str) or not version:
        raise ValueError("manifest version is required")
    if not isinstance(build_number, int) or build_number < 1:
        raise ValueError("manifest buildNumber must be positive")
    if (version, build_number) != _pubspec_version(root):
        raise ValueError("manifest version/build does not match pubspec.yaml")

    evidence = _manifest_evidence(payload, root)
    score = validate(evidence, minimum_score)
    declared_score = payload.get("qualityScore")
    if not isinstance(declared_score, int) or declared_score != score:
        raise ValueError(
            f"qualityScore mismatch: declared={declared_score!r} calculated={score}"
        )

    manual_gates = _object(payload.get("manualGates"), "manualGates")
    if set(manual_gates) != set(MANUAL_GATE_STATUSES):
        raise ValueError("manualGates must contain the exact required manual gates")
    for key, required_status in MANUAL_GATE_STATUSES.items():
        gate = _object(manual_gates[key], f"manualGates.{key}")
        if gate.get("status") != required_status:
            raise ValueError(
                f"manual gate {key} cannot be marked complete by software CI"
            )
        reason = gate.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"manual gate {key} requires an explicit reason")

    return score


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--minimum-score", type=int, default=MINIMUM_SCORE)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--expected-software-candidate-sha")
    args = parser.parse_args()

    payload = _load(args.evidence)
    if "schemaVersion" in payload:
        score = validate_manifest(
            payload,
            root=args.root.resolve(),
            minimum_score=args.minimum_score,
            expected_software_candidate_sha=args.expected_software_candidate_sha,
        )
    else:
        evidence: dict[str, bool] = {}
        for key, value in payload.items():
            if not isinstance(value, bool):
                raise ValueError(f"readiness evidence {key!r} must be boolean")
            evidence[str(key)] = value
        score = validate(evidence, args.minimum_score)
    print(f"quality_score={score}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
