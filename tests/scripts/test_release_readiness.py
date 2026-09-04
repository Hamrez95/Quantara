import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[2] / "scripts" / "release" / "release_readiness.py"
spec = importlib.util.spec_from_file_location("release_readiness", MODULE_PATH)
release_readiness = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(release_readiness)

CANDIDATE_SHA = "7" * 40


class ReleaseReadinessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "src/client/quantara_app").mkdir(parents=True)
        (self.root / "docs/releases").mkdir(parents=True)
        (self.root / "docs").mkdir(exist_ok=True)
        (self.root / "src/client/quantara_app/pubspec.yaml").write_text(
            "name: quantara_app\nversion: 1.2.0-rc.3+126\n", encoding="utf-8"
        )
        for path in (
            "docs/releases/1.2.0-rc.3-stability.md",
            "docs/releases/1.2.0-rc.3.md",
            "docs/release-rollback.md",
        ):
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("evidence\n", encoding="utf-8")

        self.manifest = {
            "schemaVersion": 1,
            "version": "1.2.0-rc.3",
            "buildNumber": 126,
            "softwareCandidateSha": CANDIDATE_SHA,
            "qualityScore": 100,
            "evidence": {
                "repository_integrity": {"passed": True, "runId": 1},
                "flutter_android_upgrade": {"passed": True, "runId": 2},
                "windows_build": {"passed": True, "runId": 3},
                "installable_artifact_smoke": {"passed": True, "artifactIds": [4, 5]},
                "stability_report": {
                    "passed": True,
                    "path": "docs/releases/1.2.0-rc.3-stability.md",
                },
                "release_notes": {
                    "passed": True,
                    "path": "docs/releases/1.2.0-rc.3.md",
                },
                "rollback_plan": {
                    "passed": True,
                    "path": "docs/release-rollback.md",
                },
                "safety_regression": {"passed": True, "runId": 2},
            },
            "manualGates": {
                "physical_device_permanent_signing": {
                    "status": "pending",
                    "reason": "Requires physical-device and permanent-signing evidence.",
                },
                "production_store_publication": {
                    "status": "approval_required",
                    "reason": "Requires explicit owner approval.",
                },
            },
        }

    def tearDown(self):
        self.temp.cleanup()

    def test_full_manifest_scores_100(self):
        self.assertEqual(
            release_readiness.validate_manifest(self.manifest, root=self.root), 100
        )

    def test_score_below_90_is_observable_and_fails_closed(self):
        evidence = {key: True for key in release_readiness.WEIGHTS}
        evidence["windows_build"] = False
        self.assertEqual(release_readiness.calculate_score(evidence), 85)
        with self.assertRaisesRegex(ValueError, "mandatory release evidence"):
            release_readiness.validate(evidence)

    def test_stale_software_candidate_sha_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "stale softwareCandidateSha"):
            release_readiness.validate_manifest(
                self.manifest,
                root=self.root,
                expected_software_candidate_sha="8" * 40,
            )

    def test_missing_stability_report_is_rejected(self):
        (self.root / "docs/releases/1.2.0-rc.3-stability.md").unlink()
        with self.assertRaisesRegex(ValueError, "path does not exist"):
            release_readiness.validate_manifest(self.manifest, root=self.root)

    def test_missing_mandatory_evidence_is_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["evidence"].pop("rollback_plan")
        with self.assertRaisesRegex(ValueError, "must be a JSON object"):
            release_readiness.validate_manifest(manifest, root=self.root)

    def test_unknown_evidence_is_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["evidence"]["physical_device_passed"] = {"passed": True}
        with self.assertRaisesRegex(ValueError, "unknown readiness evidence"):
            release_readiness.validate_manifest(manifest, root=self.root)

    def test_non_boolean_passed_field_is_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["evidence"]["repository_integrity"]["passed"] = "yes"
        with self.assertRaisesRegex(ValueError, "passed must be boolean"):
            release_readiness.validate_manifest(manifest, root=self.root)

    def test_physical_gate_cannot_be_falsely_completed(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["manualGates"]["physical_device_permanent_signing"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "cannot be marked complete"):
            release_readiness.validate_manifest(manifest, root=self.root)

    def test_publication_gate_cannot_be_falsely_completed(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["manualGates"]["production_store_publication"]["status"] = "passed"
        with self.assertRaisesRegex(ValueError, "cannot be marked complete"):
            release_readiness.validate_manifest(manifest, root=self.root)

    def test_quality_score_mismatch_is_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["qualityScore"] = 95
        with self.assertRaisesRegex(ValueError, "qualityScore mismatch"):
            release_readiness.validate_manifest(manifest, root=self.root)


if __name__ == "__main__":
    unittest.main()
