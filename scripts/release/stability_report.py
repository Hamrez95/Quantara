#!/usr/bin/env python3
"""Generate a fail-closed Quantara owner-alpha stability report.

Only explicit evidence can satisfy a gate. Software CI never implies trading,
exchange, physical-device, profitability, or restricted-live evidence.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

VALID_STATUS = {"passed", "pending", "failed"}


@dataclass(frozen=True)
class GateResult:
    name: str
    status: str
    reason: str


def _status(value: Any, *, name: str) -> str:
    if value not in VALID_STATUS:
        raise ValueError(f"{name}.status must be one of {sorted(VALID_STATUS)}")
    return str(value)


def _number(payload: dict[str, Any], key: str, *, gate: str) -> float:
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{gate}.{key} must be numeric")
    return float(value)


def evaluate_simulation(payload: dict[str, Any]) -> GateResult:
    status = _status(payload.get("status"), name="simulation_quality")
    if status != "passed":
        return GateResult("simulation_quality", status, str(payload.get("reason", "evidence not passed")))

    trades = _number(payload, "historical_trades", gate="simulation_quality")
    profit_factor = _number(payload, "profit_factor", gate="simulation_quality")
    max_drawdown = _number(payload, "max_drawdown_percent", gate="simulation_quality")
    win_rate = _number(payload, "win_rate_percent", gate="simulation_quality")
    checks = {
        "historical_trades>=350": trades >= 350,
        "profit_factor>=1.20": profit_factor >= 1.20,
        "max_drawdown<=12": max_drawdown <= 12,
        "win_rate>=45": win_rate >= 45,
    }
    failed = [label for label, ok in checks.items() if not ok]
    if failed:
        return GateResult("simulation_quality", "failed", "; ".join(failed))
    return GateResult("simulation_quality", "passed", "documented simulation thresholds satisfied")


def evaluate_paper_forward(payload: dict[str, Any]) -> GateResult:
    status = _status(payload.get("status"), name="paper_forward")
    if status != "passed":
        return GateResult("paper_forward", status, str(payload.get("reason", "evidence not passed")))

    days = _number(payload, "calendar_days", gate="paper_forward")
    signals = _number(payload, "signals", gate="paper_forward")
    profit_factor = _number(payload, "profit_factor", gate="paper_forward")
    max_drawdown = _number(payload, "max_drawdown_percent", gate="paper_forward")
    error_rate = _number(payload, "timeout_error_percent", gate="paper_forward")
    checks = {
        "calendar_days>=14": days >= 14,
        "signals>=100": signals >= 100,
        "profit_factor>=1.10": profit_factor >= 1.10,
        "max_drawdown<=10": max_drawdown <= 10,
        "timeout_error<=2": error_rate <= 2,
    }
    failed = [label for label, ok in checks.items() if not ok]
    if failed:
        return GateResult("paper_forward", "failed", "; ".join(failed))
    return GateResult("paper_forward", "passed", "documented paper-forward thresholds satisfied")


def evaluate_explicit(name: str, payload: dict[str, Any]) -> GateResult:
    status = _status(payload.get("status"), name=name)
    reason = str(payload.get("reason", "explicit evidence supplied"))
    return GateResult(name, status, reason)


def build_report(payload: dict[str, Any]) -> dict[str, Any]:
    version = payload.get("version")
    source_sha = payload.get("source_sha")
    if not isinstance(version, str) or not version.strip():
        raise ValueError("version must be a non-empty string")
    if not isinstance(source_sha, str) or len(source_sha) != 40:
        raise ValueError("source_sha must be an exact 40-character commit SHA")

    evidence = payload.get("evidence")
    if not isinstance(evidence, dict):
        raise ValueError("evidence must be an object")

    required = (
        "repository_ci",
        "flutter_android_build_smoke",
        "windows_build",
        "simulation_quality",
        "paper_forward",
        "physical_device",
    )
    missing = [name for name in required if not isinstance(evidence.get(name), dict)]
    if missing:
        raise ValueError("missing required evidence: " + ", ".join(missing))

    results = [
        evaluate_explicit("repository_ci", evidence["repository_ci"]),
        evaluate_explicit("flutter_android_build_smoke", evidence["flutter_android_build_smoke"]),
        evaluate_explicit("windows_build", evidence["windows_build"]),
        evaluate_simulation(evidence["simulation_quality"]),
        evaluate_paper_forward(evidence["paper_forward"]),
        evaluate_explicit("physical_device", evidence["physical_device"]),
    ]
    overall = "passed"
    if any(result.status == "failed" for result in results):
        overall = "failed"
    elif any(result.status != "passed" for result in results):
        overall = "pending"

    return {
        "schema_version": 1,
        "version": version,
        "source_sha": source_sha,
        "overall_status": overall,
        "gates": [result.__dict__ for result in results],
        "evidence_boundary": (
            "Software CI/build evidence does not imply simulation, paper-forward, "
            "physical-device, exchange, profitability, restricted-live, or publication readiness."
        ),
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        f"# Stability report — {report['version']}",
        "",
        f"Candidate SHA: `{report['source_sha']}`",
        f"Overall: **{str(report['overall_status']).upper()}**",
        "",
        "| Gate | Status | Evidence / reason |",
        "|---|---|---|",
    ]
    for gate in report["gates"]:
        reason = str(gate["reason"]).replace("|", "\\|").replace("\n", " ")
        lines.append(f"| `{gate['name']}` | {str(gate['status']).upper()} | {reason} |")
    lines.extend(["", f"> {report['evidence_boundary']}", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--require-passing", action="store_true")
    args = parser.parse_args()

    payload = json.loads(args.evidence.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("stability evidence must be a JSON object")
    report = build_report(payload)

    if args.json_output:
        args.json_output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.markdown_output:
        args.markdown_output.write_text(render_markdown(report), encoding="utf-8")
    print(json.dumps(report, sort_keys=True))
    if args.require_passing and report["overall_status"] != "passed":
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
