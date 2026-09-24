from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "release-readiness.yml"


class ReleaseReadinessWorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = WORKFLOW.read_text(encoding="utf-8")

    def test_flutter_evidence_can_reuse_only_unchanged_ancestor(self) -> None:
        self.assertIn("require_flutter_compatible_success()", self.source)
        self.assertIn('git merge-base --is-ancestor "$certified_sha" "$SOURCE_SHA"', self.source)
        self.assertIn('git diff --quiet "$certified_sha" "$SOURCE_SHA" --', self.source)
        self.assertIn("src/client/quantara_app", self.source)
        self.assertIn("scripts/android-cold-start-smoke.sh", self.source)
        self.assertIn("scripts/android-upgrade-smoke.sh", self.source)
        self.assertIn(".github/workflows/flutter-ci.yml", self.source)
        self.assertIn(".github/workflows/release-quantara.yml", self.source)

    def test_windows_evidence_is_pinned_to_manifest_run(self) -> None:
        self.assertIn("['evidence']['windows_build']['runId']", self.source)
        self.assertIn('actions/runs/${run_id}', self.source)
        self.assertIn('workflow_path" != ".github/workflows/windows-desktop-ci.yml"', self.source)
        self.assertIn("Quantara.ps1", self.source)
        self.assertIn("scripts/install-windows-local.ps1", self.source)
        self.assertIn('git merge-base --is-ancestor "$certified_sha" "$SOURCE_SHA"', self.source)
        self.assertIn('git diff --quiet "$certified_sha" "$SOURCE_SHA" --', self.source)
        self.assertIn(
            'windows-desktop-ci.yml certified by manifest run ${run_id}',
            self.source,
        )

    def test_one_click_installer_is_release_only_but_windows_certified(self) -> None:
        self.assertIn("Quantara\\.ps1", self.source)
        self.assertIn("scripts/install-windows-local\\.ps1", self.source)
        self.assertIn("scripts/install-windows-local.ps1", self.source)

    def test_windows_gate_is_not_truncated_before_invocation(self) -> None:
        function_start = self.source.index("require_windows_compatible_success() {")
        function_end = self.source.index("          }", function_start)
        invocation = self.source.index(
            "require_windows_compatible_success", function_end + 1
        )
        self.assertLess(function_start, function_end)
        self.assertLess(function_end, invocation)
        self.assertNotIn("\n            IFS=\n", self.source)

    def test_flutter_is_not_required_at_exact_docs_only_source_sha(self) -> None:
        self.assertIn("require_exact_success ci.yml", self.source)
        self.assertIn("require_flutter_compatible_success", self.source)
        self.assertNotIn("require_exact_success flutter-ci.yml", self.source)


if __name__ == "__main__":
    unittest.main()
