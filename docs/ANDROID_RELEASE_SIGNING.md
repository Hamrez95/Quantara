# Quantara Android signing and in-place updates

Quantara uses separate signing identities for Preview and Stable. Generic pull-request CI never needs private signing material.

## Stable package and update contract

- Stable application id: `com.quantara.quantara_app`
- Preview application id: `com.quantara.quantara_app.alpha`
- Stable releases must always use the same permanent Stable keystore and alias.
- Every Stable update must increase Android `versionCode` (Flutter build number).
- The Stable workflow verifies the APK certificate SHA-256 against the stored expected fingerprint before publication.
- Never replace or regenerate the Stable keystore after the first public Stable install. Back it up offline in at least two owner-controlled locations.

A debug-signed QA APK cannot be upgraded in place to the first Stable APK because Android requires matching signing certificates. Moving from the current debug QA install to the first permanent Stable release can therefore require one final uninstall/install. After that migration, later Stable APKs with the same signing key and a higher versionCode install as normal updates without deleting the app.

## GitHub Environment: `production`

Create these secrets only when the owner is at a trusted computer:

- `QUANTARA_ANDROID_KEYSTORE_BASE64`
- `QUANTARA_ANDROID_KEYSTORE_PASSWORD`
- `QUANTARA_ANDROID_KEY_ALIAS`
- `QUANTARA_ANDROID_KEY_PASSWORD`
- `QUANTARA_STABLE_CERT_SHA256`

`QUANTARA_STABLE_CERT_SHA256` is the SHA-256 certificate fingerprint of the selected alias, normalized with or without colons. The Stable workflow compares the decoded keystore fingerprint and the final APK signer fingerprint to this secret and fails closed on mismatch.

## GitHub Environment: `Preview`

Preview uses its own persistent signer and these secrets:

- `QUANTARA_PREVIEW_ANDROID_KEYSTORE_BASE64`
- `QUANTARA_PREVIEW_ANDROID_KEYSTORE_PASSWORD`
- `QUANTARA_PREVIEW_ANDROID_KEY_ALIAS`
- `QUANTARA_PREVIEW_ANDROID_KEY_PASSWORD`

Preview must never reuse the Stable keystore. Preview is installed beside Stable because its application id has the `.alpha` suffix.

## Release procedure

1. Merge only green development PRs into `dev`.
2. Update the release candidate version/build number and validate format, analyze, full tests, PWA build, Android debug build, and Android cold-start smoke tests.
3. Keep the `dev -> main` release PR Draft until the owner has configured and backed up the permanent signing secrets.
4. Review the final release diff and only then merge the release PR to `main`.
5. Run `Android Stable release` manually on `main` with the intended release tag.
6. Verify the uploaded APK package id, versionCode/versionName, signer fingerprint, SHA-256 checksum, and install/upgrade behavior on a physical Android device.
7. Preserve the Stable keystore forever for all future in-place updates.

Do not put keystore bytes, passwords, aliases, API keys, exchange credentials, or other secrets in Git, issue comments, build logs, or Trading Lab evidence bundles.
