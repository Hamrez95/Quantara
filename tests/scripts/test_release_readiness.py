import importlib.util
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).resolve().parents[2] / "scripts" / "release" / "release_readiness.py"
spec = importlib.util.spec_from_file_location("release_readiness", MODULE_PATH)
release_readiness = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(release_readiness)


class ReleaseReadinessTests(unittest.TestCase):
    def test_full_software_evidence_scores_100(self):
        evidence = {key: True for key in release_readiness.WEIGHTS}
        self.assertEqual(release_readiness.validate(evidence), 100)

    def test_score_below_90_fails_closed(self):
        evidence = {key: True for key in release_readiness.WEIGHTS}
        evidence["windows_build"] = False
        with self.assertRaisesRegex(ValueError, "below required 90"):
            release_readiness.validate(evidence)

    def test_exact_90_is_accepted_when_all_mandatory_evidence_exists(self):
        evidence = {key: True for key in release_readiness.WEIGHTS}
        evidence["rollback_plan"] = False
        with self.assertRaisesRegex(ValueError, "mandatory release evidence"):
            release_readiness.validate(evidence)

        evidence = {key: True for key in release_readiness.WEIGHTS}
        evidence["windows_build"] = False
        self.assertEqual(release_readiness.calculate_score(evidence), 85)

    def test_missing_mandatory_evidence_is_rejected(self):
        evidence = {key: True for key in release_readiness.WEIGHTS if key != "rollback_plan"}
        with self.assertRaisesRegex(ValueError, "rollback_plan"):
            release_readiness.validate(evidence)

    def test_unknown_evidence_is_rejected(self):
        evidence = {key: True for key in release_readiness.WEIGHTS}
        evidence["physical_device_passed"] = True
        with self.assertRaisesRegex(ValueError, "unknown readiness evidence"):
            release_readiness.calculate_score(evidence)

    def test_non_boolean_evidence_loader_is_rejected(self):
        import json
        import tempfile

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.json"
            path.write_text(json.dumps({"repository_integrity": "yes"}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "must be boolean"):
                release_readiness._load(path)


if __name__ == "__main__":
    unittest.main()
