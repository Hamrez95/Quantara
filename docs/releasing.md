# Releasing Quantara

Use **Actions → Release Quantara → Run workflow** on `main`. Select beta for device testing and stable only after successful testing. The workflow publishes signed Android APK/AAB, a PWA archive and SHA256SUMS under `quantara-vX.Y.Z`.

Required repository secret names: `QUANTARA_ANDROID_KEYSTORE_BASE64`, `QUANTARA_ANDROID_KEYSTORE_PASSWORD`, `QUANTARA_ANDROID_KEY_ALIAS`, `QUANTARA_ANDROID_KEY_PASSWORD`. Never replace the permanent signing key or commit it. Windows is not released from the current main branch.
