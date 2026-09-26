from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts" / "install-windows-local.ps1"


class WindowsOneClickInstallContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = INSTALLER.read_text(encoding="utf-8")

    def test_installer_is_exact_clean_main_only(self) -> None:
        self.assertIn("Windows install/update requires a clean worktree.", self.source)
        self.assertIn("Windows install/update requires main.", self.source)
        self.assertIn("git' @('fetch','origin','main')", self.source)
        self.assertIn("Get-GitValue @('rev-parse','origin/main')", self.source)

    def test_builds_real_installer_and_elevates_only_for_install(self) -> None:
        self.assertIn("build-windows-service.ps1", self.source)
        self.assertIn("build-windows.ps1", self.source)
        self.assertIn("installer\\windows\\Quantara.iss", self.source)
        self.assertIn("JRSoftware.InnoSetup", self.source)
        self.assertIn("-Verb RunAs", self.source)
        self.assertIn("/VERYSILENT", self.source)
        self.assertIn('/TASKS="desktopicon"', self.source)

    def test_checks_and_bootstraps_build_prerequisites_before_building(self) -> None:
        preflight = self.source.index('Ensure-WindowsBuildPrerequisites')
        service_build = self.source.index('& $WindowsServiceBuildScript')
        desktop_build = self.source.index('& $WindowsBuildScript')
        self.assertLess(preflight, service_build)
        self.assertLess(preflight, desktop_build)
        self.assertLess(self.source.index('$iscc = Get-InnoCompiler', preflight), service_build)
        self.assertIn("'Kitware.CMake'", self.source)
        self.assertIn("'Microsoft.VisualStudio.2022.BuildTools'", self.source)
        self.assertIn('Microsoft.VisualStudio.Workload.VCTools', self.source)
        self.assertIn('Windows SDK was not found', self.source)
        self.assertIn('function Refresh-ProcessPath', self.source)
        self.assertIn("[Environment]::GetEnvironmentVariable('Path', 'Machine')", self.source)
        self.assertIn('winget could not install', self.source)
        self.assertIn('CMake 3.20 or newer', self.source)

    def test_install_remains_fail_closed_then_launches_ui(self) -> None:
        self.assertIn("$ServiceName = 'QuantaraExecutionService'", self.source)
        self.assertIn("must remain stopped/disarmed after install", self.source)
        self.assertIn("serviceStateAfterInstall = 'stopped'", self.source)
        self.assertIn("Start-Process -FilePath $appExe", self.source)
        self.assertNotIn("Start-Service", self.source)

    def test_cmake_failure_is_actionable_and_service_state_is_not_changed(self) -> None:
        service_build = (ROOT / 'scripts' / 'build-windows-service.ps1').read_text(encoding='utf-8')
        self.assertIn('CMake 3.20 or newer is required.', service_build)
        self.assertIn('$LASTEXITCODE = 0', service_build)
        self.assertIn('$LASTEXITCODE = 0', self.source)
        self.assertIn('CMake installation', self.source)
        self.assertNotIn('Start-Service', self.source)

    def test_local_install_never_reads_signing_secrets(self) -> None:
        self.assertNotIn("QUANTARA_WINDOWS_PFX", self.source)
        self.assertNotIn("QUANTARA_ANDROID_KEYSTORE", self.source)


if __name__ == "__main__":
    unittest.main()
