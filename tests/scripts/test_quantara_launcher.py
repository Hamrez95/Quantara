from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "Quantara.ps1"


class QuantaraLauncherContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = LAUNCHER.read_text(encoding="utf-8")

    def test_cloud_release_uses_only_canonical_signed_workflow(self) -> None:
        self.assertIn("$ReleaseWorkflow = 'release-quantara.yml'", self.source)
        self.assertIn("'workflow','run',$ReleaseWorkflow", self.source)
        self.assertIn("include_windows=$(", self.source)
        self.assertNotIn("QUANTARA_ANDROID_KEYSTORE_", self.source)
        self.assertNotIn("QUANTARA_WINDOWS_PFX_", self.source)

    def test_cloud_release_requires_clean_exact_main(self) -> None:
        self.assertIn("Cloud release requires a clean worktree.", self.source)
        self.assertIn("Cloud release must run from main.", self.source)
        self.assertIn("git' @('fetch','origin','main')", self.source)
        self.assertIn("Get-GitValue @('rev-parse','origin/main')", self.source)
        self.assertIn("Local main is not exactly origin/main.", self.source)

    def test_stable_release_requires_explicit_owner_confirmation(self) -> None:
        self.assertIn("Type RELEASE STABLE to continue", self.source)
        self.assertIn("Stable release cancelled.", self.source)

    def test_main_sync_is_fast_forward_only_and_requires_clean_tree(self) -> None:
        self.assertIn("Sync main requires a clean worktree.", self.source)
        self.assertIn("git' @('pull','--ff-only','origin','main')", self.source)


if __name__ == "__main__":
    unittest.main()
