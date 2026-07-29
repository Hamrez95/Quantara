package com.quantara.quantara_app

import android.annotation.SuppressLint
import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "quantara/tradingview_chart",
            QuantaraChartFactory(),
        )
        configureSettingsChannel(flutterEngine)
        configureOpportunityChannel(flutterEngine)
    }

    private fun configureSettingsChannel(flutterEngine: FlutterEngine) {
        val preferences = getSharedPreferences("quantara_owner_alpha", Context.MODE_PRIVATE)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quantara/settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadAppPreferences" -> {
                    result.success(
                        mapOf(
                            "languageCode" to preferences.getString("languageCode", "fa"),
                            "themeMode" to preferences.getString("themeMode", "dark"),
                        ),
                    )
                }
                "saveAppPreferences" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val languageCode = arguments?.get("languageCode") as? String
                    val themeMode = arguments?.get("themeMode") as? String
                    if (
                        languageCode !in setOf("fa", "en") ||
                        themeMode !in setOf("light", "dark")
                    ) {
                        result.error("invalid_preferences", "App preferences are invalid.", null)
                    } else {
                        preferences.edit()
                            .putString("languageCode", languageCode)
                            .putString("themeMode", themeMode)
                            .apply()
                        result.success(null)
                    }
                }
                "loadOwnerAlphaSettings" -> {
                    if (!preferences.contains("symbols")) {
                        result.success(null)
                    } else {
                        val symbols = preferences.getString("symbols", "")
                            .orEmpty()
                            .split(',')
                            .filter { it.isNotBlank() }
                        result.success(
                            mapOf(
                                "symbols" to symbols,
                                "capital" to preferences.readExactDouble(
                                    key = "capitalBits",
                                    legacyKey = "capital",
                                    defaultValue = 10_000.0,
                                ),
                                "riskPercent" to preferences.readExactDouble(
                                    key = "riskPercentBits",
                                    legacyKey = "riskPercent",
                                    defaultValue = 1.0,
                                ),
                                "strategy" to preferences.getString(
                                    "analysisStrategy",
                                    "structureZones",
                                ),
                                "cadence" to preferences.getString(
                                    "signalCadence",
                                    "balanced",
                                ),
                            ),
                        )
                    }
                }
                "saveOwnerAlphaSettings" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val rawSymbols = arguments?.get("symbols") as? List<*>
                    val symbols = rawSymbols
                        ?.filterIsInstance<String>()
                        ?.filter { it.matches(Regex("^[A-Z0-9]{5,24}$")) }
                        ?.distinct()
                        .orEmpty()
                    val capital = (arguments?.get("capital") as? Number)?.toDouble()
                    val riskPercent = (arguments?.get("riskPercent") as? Number)?.toDouble()
                    val strategy = arguments?.get("strategy") as? String
                    val cadence = arguments?.get("cadence") as? String
                    if (
                        rawSymbols == null ||
                        symbols.size != rawSymbols.size ||
                        symbols.size !in 1..12 ||
                        capital == null ||
                        !capital.isFinite() ||
                        capital !in 100.0..100_000_000.0 ||
                        riskPercent == null ||
                        !riskPercent.isFinite() ||
                        riskPercent !in 0.1..2.0 ||
                        strategy !in setOf(
                            "structureZones",
                            "trendPullback",
                            "momentumContinuation",
                        ) ||
                        cadence !in setOf("conservative", "balanced", "active")
                    ) {
                        result.error("invalid_settings", "Owner Alpha settings are invalid.", null)
                    } else {
                        preferences.edit()
                            .putString("symbols", symbols.joinToString(","))
                            .putLong("capitalBits", capital.toBits())
                            .putLong("riskPercentBits", riskPercent.toBits())
                            .putString("analysisStrategy", strategy)
                            .putString("signalCadence", cadence)
                            .remove("capital")
                            .remove("riskPercent")
                            .apply()
                        result.success(null)
                    }
                }
                "loadStrategyLabSession" -> {
                    if (!preferences.contains("labStrategy")) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "strategy" to preferences.getString("labStrategy", ""),
                                "symbol" to preferences.getString("labSymbol", ""),
                                "timeframe" to preferences.getString("labTimeframe", ""),
                                "windowMinutes" to preferences.getInt("labWindowMinutes", 0),
                                "initialCapital" to preferences.readExactDouble(
                                    key = "labCapitalBits",
                                    legacyKey = "unusedLabCapital",
                                    defaultValue = 0.0,
                                ),
                                "riskPercent" to preferences.readExactDouble(
                                    key = "labRiskBits",
                                    legacyKey = "unusedLabRisk",
                                    defaultValue = 0.0,
                                ),
                                "startedAtMs" to preferences.getLong("labStartedAtMs", 0L),
                                "endsAtMs" to preferences.getLong("labEndsAtMs", 0L),
                            ),
                        )
                    }
                }
                "saveStrategyLabSession" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments.isNullOrEmpty()) {
                        preferences.edit()
                            .remove("labStrategy")
                            .remove("labSymbol")
                            .remove("labTimeframe")
                            .remove("labWindowMinutes")
                            .remove("labCapitalBits")
                            .remove("labRiskBits")
                            .remove("labStartedAtMs")
                            .remove("labEndsAtMs")
                            .apply()
                        result.success(null)
                    } else {
                        val strategy = arguments["strategy"] as? String
                        val symbol = arguments["symbol"] as? String
                        val timeframe = arguments["timeframe"] as? String
                        val windowMinutes = (arguments["windowMinutes"] as? Number)?.toInt()
                        val capital = (arguments["initialCapital"] as? Number)?.toDouble()
                        val risk = (arguments["riskPercent"] as? Number)?.toDouble()
                        val startedAtMs = (arguments["startedAtMs"] as? Number)?.toLong()
                        val endsAtMs = (arguments["endsAtMs"] as? Number)?.toLong()
                        if (
                            strategy !in setOf(
                                "structureZones",
                                "trendCandle",
                                "dowContinuation",
                                "kbsmResearch",
                            ) ||
                            symbol == null ||
                            !symbol.matches(Regex("^[A-Z0-9]{5,24}$")) ||
                            timeframe !in setOf("15m", "1h", "4h", "1D") ||
                            windowMinutes == null ||
                            windowMinutes !in 1..43_200 ||
                            capital == null ||
                            !capital.isFinite() ||
                            capital <= 0 ||
                            risk == null ||
                            !risk.isFinite() ||
                            risk !in 0.1..1.0 ||
                            startedAtMs == null ||
                            endsAtMs == null ||
                            endsAtMs <= startedAtMs
                        ) {
                            result.error(
                                "invalid_strategy_lab_session",
                                "Strategy Lab session is invalid.",
                                null,
                            )
                        } else {
                            preferences.edit()
                                .putString("labStrategy", strategy)
                                .putString("labSymbol", symbol)
                                .putString("labTimeframe", timeframe)
                                .putInt("labWindowMinutes", windowMinutes)
                                .putLong("labCapitalBits", capital.toBits())
                                .putLong("labRiskBits", risk.toBits())
                                .putLong("labStartedAtMs", startedAtMs)
                                .putLong("labEndsAtMs", endsAtMs)
                                .apply()
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun configureOpportunityChannel(flutterEngine: FlutterEngine) {
        val preferences = getSharedPreferences("quantara_owner_alpha", Context.MODE_PRIVATE)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quantara/opportunities",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "loadOpportunityState" -> {
                    result.success(
                        mapOf(
                            "notificationsEnabled" to preferences.getBoolean(
                                "setupNotificationsEnabled",
                                false,
                            ),
                            "takenSetupIds" to preferences
                                .getStringSet("takenSetupIds", emptySet())
                                .orEmpty()
                                .toList(),
                            "notifiedSetupIds" to preferences
                                .getStringSet("notifiedSetupIds", emptySet())
                                .orEmpty()
                                .toList(),
                            "journalJson" to preferences.getString(
                                "signalJournalJson",
                                "[]",
                            ),
                        ),
                    )
                }
                "saveOpportunityState" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val enabled = arguments?.get("notificationsEnabled") as? Boolean
                    val taken = arguments?.readSetupIds("takenSetupIds")
                    val notified = arguments?.readSetupIds("notifiedSetupIds")
                    val journalJson = arguments?.get("journalJson") as? String
                    if (
                        enabled == null ||
                        taken == null ||
                        notified == null ||
                        journalJson == null ||
                        journalJson.length > 200_000
                    ) {
                        result.error("invalid_opportunity_state", "Opportunity state is invalid.", null)
                    } else {
                        preferences.edit()
                            .putBoolean("setupNotificationsEnabled", enabled)
                            .putStringSet("takenSetupIds", taken)
                            .putStringSet("notifiedSetupIds", notified)
                            .putString("signalJournalJson", journalJson)
                            .apply()
                        result.success(null)
                    }
                }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "openBackgroundSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "showSetupNotification" -> {
                    showSetupNotification(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.success(false)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val granted =
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            notificationPermissionResult?.success(granted)
            notificationPermissionResult = null
        }
    }

    private fun showSetupNotification(arguments: Map<*, *>?) {
        if (arguments == null) return
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val setupId = arguments["setupId"] as? String ?: return
        val symbol = arguments["symbol"] as? String ?: return
        val timeframe = arguments["timeframe"] as? String ?: return
        val direction = arguments["direction"] as? String ?: return
        val entryLower = (arguments["entryLower"] as? Number)?.toDouble() ?: return
        val entryUpper = (arguments["entryUpper"] as? Number)?.toDouble() ?: return
        val stopLoss = (arguments["stopLoss"] as? Number)?.toDouble() ?: return
        val targets = (arguments["targets"] as? List<*>)
            ?.filterIsInstance<Number>()
            ?.map { it.toDouble() }
            ?: return
        val leverage = (arguments["leverage"] as? Number)?.toInt() ?: return
        val persian = arguments["languageCode"] != "en"
        if (targets.size != 3 || setupId.length > 320) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    SETUP_CHANNEL_ID,
                    if (persian) "ستاپ‌های معاملاتی Quantara" else "Quantara setups",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = if (persian) {
                        "هشدار ستاپ تازه پس از اسکن بازار"
                    } else {
                        "New market setup alerts after a scan"
                    }
                },
            )
        }
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            setupId.hashCode(),
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val directionLabel = if (persian) {
            if (direction == "long") "خرید" else "فروش"
        } else {
            direction.uppercase()
        }
        val title = if (persian) {
            "ستاپ $directionLabel · $symbol · $timeframe"
        } else {
            "$directionLabel setup · $symbol · $timeframe"
        }
        val details = if (persian) {
            "ورود ${entryLower.pretty()}–${entryUpper.pretty()} | SL ${stopLoss.pretty()} | " +
                "TP ${targets.joinToString(" / ") { it.pretty() }} | اهرم پیشنهادی ${leverage}x"
        } else {
            "Entry ${entryLower.pretty()}–${entryUpper.pretty()} | SL ${stopLoss.pretty()} | " +
                "TP ${targets.joinToString(" / ") { it.pretty() }} | Suggested ${leverage}x"
        }
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, SETUP_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }.setSmallIcon(R.drawable.ic_quantara_launcher)
            .setContentTitle(title)
            .setContentText(details)
            .setStyle(android.app.Notification.BigTextStyle().bigText(details))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(android.app.Notification.CATEGORY_RECOMMENDATION)
            .build()
        manager.notify(setupId.hashCode(), notification)
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 4107
        private const val SETUP_CHANNEL_ID = "quantara_setup_alerts_v1"
    }
}

private fun Map<*, *>.readSetupIds(key: String): Set<String>? {
    val values = this[key] as? List<*> ?: return null
    val ids = values.filterIsInstance<String>()
        .filter { it.isNotEmpty() && it.length <= 320 }
        .take(250)
        .toSet()
    return if (ids.size == values.size) ids else null
}

private fun Double.pretty(): String =
    when {
        this >= 1000 -> String.format(java.util.Locale.US, "%.2f", this)
        this >= 1 -> String.format(java.util.Locale.US, "%.4f", this)
        else -> String.format(java.util.Locale.US, "%.6f", this)
    }

private fun SharedPreferences.readExactDouble(
    key: String,
    legacyKey: String,
    defaultValue: Double,
): Double {
    if (contains(key)) {
        return Double.fromBits(getLong(key, defaultValue.toBits()))
    }
    return getFloat(legacyKey, defaultValue.toFloat()).toDouble()
}

private class QuantaraChartFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return QuantaraChartView(context, args as? Map<*, *>)
    }
}

private class QuantaraChartView(
    private val context: Context,
    arguments: Map<*, *>?,
) : PlatformView {
    private val payload = JSONObject(arguments ?: emptyMap<Any, Any>()).toString()
    private val webView = createWebView()

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(): WebView {
        return WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.domStorageEnabled = false
            settings.databaseEnabled = false
            settings.allowContentAccess = false
            settings.allowFileAccess = true
            settings.blockNetworkLoads = true
            settings.setGeolocationEnabled(false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                settings.safeBrowsingEnabled = true
            }
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
            isLongClickable = false
            setOnLongClickListener { true }
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    view.evaluateJavascript("window.renderQuantaraChart($payload)", null)
                }

                override fun shouldOverrideUrlLoading(
                    view: WebView,
                    request: WebResourceRequest,
                ): Boolean {
                    val uri = request.url
                    if (uri.scheme == "https" && uri.host == "www.tradingview.com") {
                        context.startActivity(Intent(Intent.ACTION_VIEW, uri))
                    }
                    return true
                }

            }
            loadUrl("file:///android_asset/tradingview/chart.html")
        }
    }

    override fun getView(): View = webView

    override fun dispose() {
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.removeAllViews()
        webView.destroy()
    }
}
