package com.quantara.quantara_app

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Minimal launch activity for Android 16.
 *
 * The legacy chart WebView and large persistence/notification channel surface
 * stay out of the activity. The only custom channel opens Android's app settings;
 * notifications and persistence use maintained Flutter plugins.
 */
class SafeMainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quantara/opportunities",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openBackgroundSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        }
    }
}
