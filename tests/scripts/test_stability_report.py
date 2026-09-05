import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[2] / "scripts/release/stability_report.py"
SPEC = importlib.util.spec_from_file_location("stability_report", MODULE_PATH)
assert SPEC and SPEC.loader
stability_report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stability_report)

CANDIDATE_SHA = "7764cf362348d66fa956aeebe154d8198a2f9370"


def _base_payload():
    return {
        "schemaVersion": 1,
        "version": "1.2.0-rc.3",
        "buildNumber": 126,
        "softwareCandidateSha": CANDIDATE_SHA,
        "overallStatus": "pending",
        "gates": {
            "software": {
                "status": "passed",
                "reason": "automated software evidence passed",
                "readinessManifest": "docs/releases/current-readiness.json",
            },
            "simulation": {
                "status": "pending",
                "reason": "research evidence pending",
                "requirements": {key: False for key in stability_report.SIMULATION_REQUIREMENTS},
            },
            "strategy_promotion": {
                "status": "pending",
                "reason": "strategy metrics pending",
                "metrics": {
                    key: {"observed": False, "value": None}
                    for key in stability_report.STRATEGY_METRICS
                },
            },
            "paper_shadow": {
                "status": "pending",
                "reason": "paper/shadow evidence pending",
                "requirements": {key: False for key in stability_report.PAPER_REQUIREMENTS},
            },
            "physical_device_signing": {
                "status": "pending",
                "reason": "physical evidence pending",
                "evidenceRefs": [],
            },
            "exchange_restricted_live": {
                "status": "pending",
                "reason": "exchange evidence pending",
                "evidenceRefs": [],
            },
        },
    }


class StabilityReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        app = self.root / "src/client/quantara_app"
        app.mkdir(parents=True)
        (app / "pubspec.yaml").write_text("version: 1.2.0-rc.3+126\n", encoding="utf-8")
        releases = self.root / "docs/releases"
        releases.mkdir(parents=True)
        (releases / "current-readiness.json").write_text(
            json.dumps(
                {
                    "version": "1.2.0-rc.3",
                    "buildNumber": 126,
                    "softwareCandidateSha": CANDIDATE_SHA,
                    "qualityScore": 100,
                    "minimumQualityScore": 90,
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self):
        self.temp.cleanup()

    def validate(self, payload):
        return stability_report.validate_report(payload, root=self.root)

    def test_current_software_pass_remains_overall_pending(self):
        result = self.validate(_base_payload())
        self.assertEqual("pending", result.overall_status)
        self.assertEqual("passed", result.gate_statuses["software"])

    def test_missing_gate_fails_closed(self):
        payload = _base_payload()
        del payload["gates"]["paper_shadow"]
        with self.assertRaisesRegex(ValueError, "stability gates must be exact"):
            self.validate(payload)

    def test_stale_candidate_sha_is_rejected(self):
        payload = _base_payload()
        with self.assertRaisesRegex(ValueError, "stale softwareCandidateSha"):
            stability_report.validate_report(
                payload,
                root=self.root,
                expected_candidate_sha="0" * 40,
            )

    def test_software_pass_below_quality_threshold_is_rejected(self):
        readiness = self.root / "docs/releases/current-readiness.json"
        data = json.loads(readiness.read_text(encoding="utf-8"))
        data["qualityScore"] = 89
        readiness.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "below readiness minimum"):
            self.validate(_base_payload())

    def test_simulation_cannot_pass_with_missing_requirement(self):
        payload = _base_payload()
        payload["gates"]["simulation"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "simulation gate cannot pass"):
            self.validate(payload)

    def test_strategy_promotion_cannot_pass_with_unobserved_metric(self):
        payload = _base_payload()
        payload["gates"]["strategy_promotion"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "unobserved required metrics"):
            self.validate(payload)

    def test_paper_shadow_cannot_pass_with_missing_requirement(self):
        payload = _base_payload()
        payload["gates"]["paper_shadow"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "paper/shadow gate cannot pass"):
            self.validate(payload)

    def test_physical_gate_cannot_pass_without_evidence_refs(self):
        payload = _base_payload()
        payload["gates"]["physical_device_signing"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "cannot pass without explicit evidenceRefs"):
            self.validate(payload)

    def test_failed_gate_makes_overall_failed(self):
        payload = _base_payload()
        payload["gates"]["paper_shadow"]["status"] = "failed"
        payload["overallStatus"] = "failed"
        result = self.validate(payload)
        self.assertEqual("failed", result.overall_status)

    def test_all_explicit_passes_allow_overall_pass(self):
        payload = _base_payload()
        payload["overallStatus"] = "passed"
        payload["gates"]["simulation"]["status"] = "passed"
        payload["gates"]["simulation"]["requirements"] = {
            key: True for key in stability_report.SIMULATION_REQUIREMENTS
        }
        payload["gates"]["strategy_promotion"]["status"] = "passed"
        payload["gates"]["strategy_promotion"]["metrics"] = {
            key: {"observed": True, "value": 1}
            for key in stability_report.STRATEGY_METRICS
        }
        payload["gates"]["paper_shadow"]["status"] = "passed"
        payload["gates"]["paper_shadow"]["requirements"] = {
            key: True for key in stability_report.PAPER_REQUIREMENTS
        }
        for gate in ("physical_device_signing", "exchange_restricted_live"):
            payload["gates"][gate]["status"] = "passed"
            payload["gates"][gate]["evidenceRefs"] = ["verified:test-evidence"]
        result = self.validate(payload)
        self.assertEqual("passed", result.overall_status)

    def test_rendered_report_states_pending_boundary(self):
        payload = _base_payload()
        result = self.validate(payload)
        rendered = stability_report.render_markdown(payload, result)
        self.assertIn("Overall status: **PENDING**", rendered)
        self.assertIn("Missing evidence remains PENDING", rendered)


if __name__ == "__main__":
    unittest.main()
