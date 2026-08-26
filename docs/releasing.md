# Releasing Quantara

The canonical release source is `dev`. A release is cloud-first: open **Actions → Release Quantara → Run workflow**, choose a patch/minor/major bump and beta/stable channel, then add optional notes. The workflow validates `dev`, quality gates, Android identity and signing before it creates `quantara-vX.Y.Z` and a GitHub Release. A failed build creates neither tag nor release.

`MAJOR.MINOR.PATCH` is semantic versioning. Beta versions are immutable (`-beta.1`, then `-beta.2`); stable artifacts are never replaced—make a new patch release instead.

Local validation is `./scripts/release.ps1`. It uses the same dependency-free version calculator as Actions, checks a clean `dev` worktree and deliberately delegates publishing to GitHub Actions. Local artifact builds remain available through `./scripts/build-release.ps1`.

Android requires the existing permanent Quantara signing identity. Actions expects only these secret names: `QUANTARA_ANDROID_KEYSTORE_BASE64`, `QUANTARA_ANDROID_KEYSTORE_PASSWORD`, `QUANTARA_ANDROID_KEY_ALIAS`, `QUANTARA_ANDROID_KEY_PASSWORD`. Never commit a keystore or password. Keep an encrypted offline backup of the original key; GitHub Secrets are not a backup. Missing signing material blocks release rather than producing an update-incompatible APK.

Current supported release artifacts are Android APK/AAB and the GitHub Pages PWA. Windows/iOS are not released by this workflow. APK/AAB checksums are published in `SHA256SUMS.txt`.
