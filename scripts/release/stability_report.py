#!/usr/bin/env python3
"""Generate and validate Quantara owner-alpha stability reports.

This contract intentionally separates automated software evidence from research,
paper-forward, physical-device, exchange, and publication evidence. Missing or
unobserved evidence is never promoted to PASS.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, NamedTuple

VALID_STATUSES = frozenset({"passed", "pending", "failed"})
REQUIRED_GATES = (
    "software",
    "simulation",
    "strategy_promotion",
    "paper_shadow",
    "physical_device_signing",
    "exchange_restricted_live",
)
_SHA = re.compile(r"^[0-9a-f]{40}$")
_VERSION = re.compile(r"^version:\s*([^+\s]+)\+([0-9]+)\s*$")

# These are requirements explicitly named by docs/quality-gates.md. The source
# document deliberately does not prescribe universal profit/drawdown cutoffs;
# therefore this validator requires evidence for the named metrics without
# inventing numeric trading thresholds.
SIMULATION_REQUIREMENTS = frozenset(
    {
        "datasetProvenance",
        "immutableConfiguration",
        "chronologicalPartitions",
        "walkForwardOutOfSample",
        "realisticCostsAndFills",
        "regimeBreakdown",
        "parameterSensitivity",
        "baselineComparison",
        "completeTradeLedger",
        "lookAheadLeakageChecks",
    }
)
STRATEGY_METRICS = frozenset(
    {
        "expectancy",
        "profitFactor",
        "maximumDrawdown",
        "returnToDrawdown",
        "tailLosses",
        "exposureTime",
        "turnover",
        "tradeCount",
        "confidenceIntervals",
        "foldAndRegimeStability",
    }
)
PAPER_REQUIREMENTS = frozenset(
    {
        "accountingReconciliation",
        "restartRecoveryReconciliation",
        "shadowLiveMarketDecisions",
        "multipleMarketRegimes",
        "operationalFailureCoverage",
        "emergencyControlsAcceptance",
    }
)


class ValidationResult(NamedTuple):
    overall_status: str
    gate_statuses: dict[str, str]


def _object(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be a JSON object")
    return value


def _pubspec_identity(root: Path) -> tuple[str, int]:
    pubspec = root / "src/client/quantara_app/pubspec.yaml"
    for raw_line in pubspec.read_text(encoding="utf-8").splitlines():
        match = _VERSION.match(raw_line.strip())
        if match:
            return match.group(1), int(match.group(2))
    raise ValueError("pubspec.yaml has no parseable version/build number")


def _require_bool_map(record: dict[str, Any], field: str, required: frozenset[str]) -> None:
    values = _object(record.get(field), field)
    missing = sorted(required - set(values))
    unknown = sorted(set(values) - required)
    if missing:
        raise ValueError(f"{field} missing requirements: {', '.join(missing)}")
    if unknown:
        raise ValueError(f"{field} has unknown requirements: {', '.join(unknown)}")
    for key, value in values.items():
        if not isinstance(value, bool):
            raise ValueError(f"{field}.{key} must be boolean")


def _require_metric_map(record: dict[str, Any]) -> None:
    metrics = _object(record.get("metrics"), "strategy_promotion.metrics")
    missing = sorted(STRATEGY_METRICS - set(metrics))
    unknown = sorted(set(metrics) - STRATEGY_METRICS)
    if missing:
        raise ValueError("strategy_promotion.metrics missing: " + ", ".join(missing))
    if unknown:
        raise ValueError("strategy_promotion.metrics unknown: " + ", ".join(unknown))
    for key, value in metrics.items():
        if not isinstance(value, dict):
            raise ValueError(f"strategy_promotion.metrics.{key} must be an object")
        observed = value.get("observed")
        if not isinstance(observed, bool):
            raise ValueError(f"strategy_promotion.metrics.{key}.observed must be boolean")
        if observed and value.get("value") is None:
            raise ValueError(f"strategy_promotion.metrics.{key} is observed without value")


def _gate_reason(record: dict[str, Any], name: str) -> str:
    reason = record.get("reason")
    if not isinstance(reason, str) or not reason.strip():
        raise ValueError(f"gates.{name}.reason must be a non-empty string")
    return reason.strip()


def validate_report(
    payload: dict[str, Any],
    *,
    root: Path,
    expected_candidate_sha: str | None = None,
) -> ValidationResult:
    if payload.get("schemaVersion") != 1:
        raise ValueError("unsupported stability report schemaVersion")

    candidate_sha = payload.get("softwareCandidateSha")
    if not isinstance(candidate_sha, str) or not _SHA.fullmatch(candidate_sha):
        raise ValueError("softwareCandidateSha must be a lowercase 40-character SHA")
    if expected_candidate_sha is not None and candidate_sha != expected_candidate_sha.lower():
        raise ValueError(
            f"stale softwareCandidateSha: report={candidate_sha} expected={expected_candidate_sha.lower()}"
        )

    version = payload.get("version")
    build_number = payload.get("buildNumber")
    if not isinstance(version, str) or not version:
        raise ValueError("version is required")
    if not isinstance(build_number, int) or build_number < 1:
        raise ValueError("buildNumber must be positive")
    if (version, build_number) != _pubspec_identity(root):
        raise ValueError("stability report version/build does not match pubspec.yaml")

    gates = _object(payload.get("gates"), "gates")
    if set(gates) != set(REQUIRED_GATES):
        missing = sorted(set(REQUIRED_GATES) - set(gates))
        unknown = sorted(set(gates) - set(REQUIRED_GATES))
        raise ValueError(
            "stability gates must be exact; "
            f"missing={','.join(missing) or 'none'} unknown={','.join(unknown) or 'none'}"
        )

    statuses: dict[str, str] = {}
    for name in REQUIRED_GATES:
        record = _object(gates[name], f"gates.{name}")
        status = record.get("status")
        if status not in VALID_STATUSES:
            raise ValueError(f"gates.{name}.status must be passed/pending/failed")
        _gate_reason(record, name)
        statuses[name] = str(status)

    software = _object(gates["software"], "gates.software")
    readiness_path = software.get("readinessManifest")
    if not isinstance(readiness_path, str) or not readiness_path.strip():
        raise ValueError("gates.software.readinessManifest is required")
    readiness_file = root / readiness_path
    if not readiness_file.is_file():
        raise ValueError("software readiness manifest does not exist")
    readiness = json.loads(readiness_file.read_text(encoding="utf-8"))
    if readiness.get("softwareCandidateSha") != candidate_sha:
        raise ValueError("software readiness manifest candidate SHA differs from stability report")
    if readiness.get("version") != version or readiness.get("buildNumber") != build_number:
        raise ValueError("software readiness manifest version/build differs from stability report")
    if software.get("status") == "passed" and readiness.get("qualityScore", -1) < readiness.get(
        "minimumQualityScore", 90
    ):
        raise ValueError("software gate cannot pass below readiness minimum quality score")

    simulation = _object(gates["simulation"], "gates.simulation")
    _require_bool_map(simulation, "requirements", SIMULATION_REQUIREMENTS)
    if simulation.get("status") == "passed" and not all(simulation["requirements"].values()):
        raise ValueError("simulation gate cannot pass with unmet quality-gate requirements")

    strategy = _object(gates["strategy_promotion"], "gates.strategy_promotion")
    _require_metric_map(strategy)
    if strategy.get("status") == "passed" and not all(
        item["observed"] for item in strategy["metrics"].values()
    ):
        raise ValueError("strategy promotion cannot pass with unobserved required metrics")

    paper = _object(gates["paper_shadow"], "gates.paper_shadow")
    _require_bool_map(paper, "requirements", PAPER_REQUIREMENTS)
    if paper.get("status") == "passed" and not all(paper["requirements"].values()):
        raise ValueError("paper/shadow gate cannot pass with unmet requirements")

    for name in ("physical_device_signing", "exchange_restricted_live"):
        record = _object(gates[name], f"gates.{name}")
        if record.get("status") == "passed":
            evidence_refs = record.get("evidenceRefs")
            if not isinstance(evidence_refs, list) or not evidence_refs:
                raise ValueError(f"{name} cannot pass without explicit evidenceRefs")
            if not all(isinstance(item, str) and item.strip() for item in evidence_refs):
                raise ValueError(f"{name}.evidenceRefs must contain non-empty strings")

    if any(status == "failed" for status in statuses.values()):
        overall = "failed"
    elif all(status == "passed" for status in statuses.values()):
        overall = "passed"
    else:
        overall = "pending"

    declared = payload.get("overallStatus")
    if declared != overall:
        raise ValueError(f"overallStatus mismatch: declared={declared!r} calculated={overall}")

    return ValidationResult(overall_status=overall, gate_statuses=statuses)


def render_markdown(payload: dict[str, Any], result: ValidationResult) -> str:
    lines = [
        f"# Quantara {payload['version']} owner-alpha stability report",
        "",
        f"Software candidate SHA: `{payload['softwareCandidateSha']}`  ",
        f"Version/build: `{payload['version']}+{payload['buildNumber']}`  ",
        f"Overall status: **{result.overall_status.upper()}**",
        "",
        "| Gate | Status | Reason |",
        "| --- | --- | --- |",
    ]
    for name in REQUIRED_GATES:
        record = payload["gates"][name]
        reason = str(record["reason"]).replace("|", "\\|")
        lines.append(f"| `{name}` | **{result.gate_statuses[name].upper()}** | {reason} |")
    lines.extend(
        [
            "",
            "A PASS for automated software evidence does not imply strategy profitability, physical-device behavior, exchange correctness, restricted-live readiness, or publication approval.",
            "Missing evidence remains PENDING; it is never inferred from CI.",
            "",
            "The machine-readable source for this report is `docs/releases/current-stability.json`; validate or regenerate it with `scripts/release/stability_report.py`.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--expected-candidate-sha")
    parser.add_argument("--write-markdown", type=Path)
    args = parser.parse_args()

    payload = json.loads(args.report.read_text(encoding="utf-8"))
    payload = _object(payload, "stability report")
    result = validate_report(
        payload,
        root=args.root.resolve(),
        expected_candidate_sha=args.expected_candidate_sha,
    )
    if args.write_markdown is not None:
        args.write_markdown.write_text(render_markdown(payload, result), encoding="utf-8")
    print(f"overall_status={result.overall_status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
