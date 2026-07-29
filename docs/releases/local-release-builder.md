# Quantara local release builder

The PowerShell release builder keeps local builds predictable without requiring
you to remember Flutter commands.

## Quick start on Windows

1. Install Flutter, Git, Android Studio and an Android SDK.
2. Open PowerShell in the Quantara repository.
3. Confirm that `flutter doctor -v` has no blocking Android errors.
4. Run:

```powershell
.\scripts\build-release.ps1
```

The default command runs package restore, static analysis, tests and a release
APK build. It copies the final APK into `release-artifacts`, creates
`SHA256SUMS.txt`, and records the Git commit and file hashes in
`build-manifest.json`.

## Common commands

```powershell
# Universal Android APK for direct installation
.\scripts\build-release.ps1 -Target AndroidApk

# Android App Bundle for Google Play
.\scripts\build-release.ps1 -Target AndroidBundle -Clean

# APK, App Bundle and Web package
.\scripts\build-release.ps1 -Target All -OpenOutput

# Windows desktop package (must run on Windows)
.\scripts\build-release.ps1 -Target Windows

# Show built-in help
Get-Help .\scripts\build-release.ps1 -Detailed
```

The script stops when the Git checkout has uncommitted files. This protects
release traceability. `-AllowDirty` is available for a private test build, but
should not be used for a published release.

Platform builds must run on their platform: Windows on Windows, Linux on Linux,
and macOS/iOS on macOS. Android and Web can be built on Windows.
