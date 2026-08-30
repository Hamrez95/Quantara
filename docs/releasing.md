# Releasing Quantara

The canonical release source is `main`. Product changes enter through `dev`, pass the required repository, Flutter, Android-upgrade and Windows checks, and are synchronized into `main` through a reviewed pull request before publication.

A release is cloud-first: open **Actions → Release Quantara → Run workflow** on `main`, choose a patch/minor/major bump and beta/stable channel, select the staged-rollout percentage, and add optional notes. The workflow requires a successful Flutter client CI run for the exact current `main` commit before it publishes anything.

`MAJOR.MINOR.PATCH` is semantic versioning. Beta versions are immutable (`-beta.1`, then the next calculated beta); stable artifacts are never replaced. Make a new release instead of overwriting a tag or artifact.

The workflow validates formatting, analysis and tests; Android package/signing identity; monotonically increasing build number; previous-release identity continuity; checksums; and the machine-readable update manifest. A failed build creates no published release. Android APK/AAB and the PWA archive are always produced. A Windows x64 installer is included only when explicitly requested and its protected signing configuration passes.

Android uses the permanent Quantara signing identity. Actions expects these secrets: `QUANTARA_ANDROID_KEYSTORE_BASE64`, `QUANTARA_ANDROID_KEYSTORE_PASSWORD`, `QUANTARA_ANDROID_KEY_ALIAS`, and `QUANTARA_ANDROID_KEY_PASSWORD`. Never commit a keystore or password. Keep an encrypted offline backup of the original key; GitHub Secrets are not a backup. Missing signing material blocks the release rather than producing an update-incompatible APK.

Local validation is `./scripts/release.ps1`. Local artifact builds remain available through `./scripts/build-release.ps1`, but canonical publication is performed only by GitHub Actions from certified `main`.
