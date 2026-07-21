package com.quantara.quantara_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
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
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "quantara/tradingview_chart",
            QuantaraChartFactory(),
        )
        configureSettingsChannel(flutterEngine)
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
                    if (
                        rawSymbols == null ||
                        symbols.size != rawSymbols.size ||
                        symbols.size !in 1..12 ||
                        capital == null ||
                        !capital.isFinite() ||
                        capital !in 100.0..100_000_000.0 ||
                        riskPercent == null ||
                        !riskPercent.isFinite() ||
                        riskPercent !in 0.1..5.0
                    ) {
                        result.error("invalid_settings", "Owner Alpha settings are invalid.", null)
                    } else {
                        preferences.edit()
                            .putString("symbols", symbols.joinToString(","))
                            .putLong("capitalBits", capital.toBits())
                            .putLong("riskPercentBits", riskPercent.toBits())
                            .remove("capital")
                            .remove("riskPercent")
                            .apply()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
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
