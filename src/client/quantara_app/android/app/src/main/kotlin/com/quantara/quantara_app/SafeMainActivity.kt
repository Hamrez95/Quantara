package com.quantara.quantara_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Minimal launch activity for Android 16.
 *
 * The legacy chart renderer and large persistence/notification channel surface
 * stay out of the activity. Custom channels are deliberately narrow: app
 * settings and a user-confirmed handoff of an already verified APK to Android's
 * normal package installer.
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quantara/app_updates",
        ).setMethodCallHandler { call, result ->
            if (call.method != "installVerifiedApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val rawPath = call.argument<String>("path")
            if (rawPath.isNullOrBlank()) {
                result.error("invalid_apk_path", "Verified APK path is missing.", null)
                return@setMethodCallHandler
            }
            handoffVerifiedApk(rawPath, result)
        }
    }

    private fun handoffVerifiedApk(rawPath: String, result: MethodChannel.Result) {
        val updateRoot = File(cacheDir, "quantara-updates")
        val apk = File(rawPath)
        val canonicalRoot: File
        val canonicalApk: File
        try {
            canonicalRoot = updateRoot.canonicalFile
            canonicalApk = apk.canonicalFile
        } catch (_: IOException) {
            result.error("invalid_apk_path", "Verified APK path cannot be resolved.", null)
            return
        }

        val rootPrefix = canonicalRoot.path + File.separator
        if (!canonicalApk.path.startsWith(rootPrefix) ||
            !canonicalApk.isFile ||
            !canonicalApk.name.lowercase().endsWith(".apk")
        ) {
            result.error(
                "invalid_apk_path",
                "Package installer handoff is limited to Quantara's verified update cache.",
                null,
            )
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            result.error(
                "install_permission_required",
                "Android has not allowed Quantara to request package installs.",
                null,
            )
            return
        }

        val uri = try {
            FileProvider.getUriForFile(
                this,
                "$packageName.quantara-update-files",
                canonicalApk,
            )
        } catch (_: IllegalArgumentException) {
            result.error("invalid_apk_path", "Verified APK is outside the allowed provider path.", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(intent)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("installer_unavailable", "Android package installer is unavailable.", null)
        } catch (_: SecurityException) {
            result.error("installer_blocked", "Android blocked the package installer handoff.", null)
        }
    }
}
