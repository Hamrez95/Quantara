package com.quantara.quantara_app

import io.flutter.embedding.android.FlutterActivity

/**
 * Minimal launch activity for the Android 16 cold-start hotfix.
 *
 * Optional native channels and the legacy WebView platform view are kept out of
 * the launch path until physical-device smoke tests prove they are safe.
 */
class SafeMainActivity : FlutterActivity()
