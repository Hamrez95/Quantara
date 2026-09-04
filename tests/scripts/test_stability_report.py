import importlib.util
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).resolve().parents[2] / "scripts" / "release" / "stability_report.py"
spec = importlib.util.spec_from_file_location("stability_report", MODULE_PATH)
stability_report = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(stability_report)


def evidence():
    return {
        "version": "1.2.0-rc.3",
        "source_sha": "a" * 40,
        "evidence": {
            "repository_ci": {"status": "passed", "reason": "CI"},
            "flutter_android_build_smoke": {"status": "passed", "reason": "APK + upgrade CI"},
            "windows_build": {"status": "passed", "reason": "Windows CI"},
            "simulation_quality": {
                "status": "passed",
                "historical_trades": 350,
                "profit_factor": 1.20,
                "max_drawdown_percent": 12,
                "win_rate_percent": 45,
            },
            "paper_forward": {
                "status": "passed",
                "calendar_days": 14,
                "signals": 100,
                "profit_factor": 1.10,
                "max_drawdown_percent": 10,
                "timeout_error_percent": 2,
            },
            "physical_device": {"status": "passed", "reason": "explicit operator evidence"},
        },
    }


class StabilityReportTests(unittest.TestCase):
    def test_all_documented_thresholds_can_pass(self):
        report = stability_report.build_report(evidence())
        self.assertEqual(report["overall_status"], "passed")

    def test_missing_real_world_evidence_never_becomes_pass(self):
        payload = evidence()
        payload["evidence"]["paper_forward"] = {"status": "pending", "reason": "not observed"}
        payload["evidence"]["physical_device"] = {"status": "pending", "reason": "not observed"}
        report = stability_report.build_report(payload)
        self.assertEqual(report["overall_status"], "pending")

    def test_simulation_threshold_failure_is_failed(self):
        payload = evidence()
        payload["evidence"]["simulation_quality"]["historical_trades"] = 349
        report = stability_report.build_report(payload)
        gate = next(g for g in report["gates"] if g["name"] == "simulation_quality")
        self.assertEqual(gate["status"], "failed")
        self.assertEqual(report["overall_status"], "failed")

    def test_paper_forward_threshold_failure_is_failed(self):
        payload = evidence()
        payload["evidence"]["paper_forward"]["timeout_error_percent"] = 2.01
        report = stability_report.build_report(payload)
        gate = next(g for g in report["gates"] if g["name"] == "paper_forward")
        self.assertEqual(gate["status"], "failed")

    def test_missing_gate_is_rejected(self):
        payload = evidence()
        del payload["evidence"]["physical_device"]
        with self.assertRaisesRegex(ValueError, "missing required evidence"):
            stability_report.build_report(payload)

    def test_invalid_sha_is_rejected(self):
        payload = evidence()
        payload["source_sha"] = "short"
        with self.assertRaisesRegex(ValueError, "40-character"):
            stability_report.build_report(payload)

    def test_software_ci_does_not_fill_other_evidence(self):
        payload = evidence()
        payload["evidence"]["simulation_quality"] = {"status": "pending", "reason": "no dataset evidence"}
        payload["evidence"]["paper_forward"] = {"status": "pending", "reason": "no forward-run evidence"}
        report = stability_report.build_report(payload)
        self.assertEqual(report["overall_status"], "pending")
        self.assertIn("does not imply simulation", report["evidence_boundary"])


if __name__ == "__main__":
    unittest.main()
