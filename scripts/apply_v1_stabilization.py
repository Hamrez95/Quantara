from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise RuntimeError(f"Patch anchor not found in {path}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# App version and bundled crypto icon font.
# ---------------------------------------------------------------------------
pubspec = "src/client/quantara_app/pubspec.yaml"
replace_once(pubspec, "version: 0.13.2+18", "version: 1.0.0+100")
replace_once(pubspec, "  crypto: ^3.0.7\n", "  crypto: ^3.0.7\n  crypto_icons: ^1.0.0\n")
replace_once(
    pubspec,
    """        - asset: assets/fonts/Vazirmatn-Bold.ttf
          weight: 700
""",
    """        - asset: assets/fonts/Vazirmatn-Bold.ttf
          weight: 700
    - family: CryptocurrencyIcons
      fonts:
        - asset: packages/crypto_icons/assets/fonts/cryptocurrency-icons.ttf
""",
)

# ---------------------------------------------------------------------------
# True crypto glyphs with deterministic fallback.
# ---------------------------------------------------------------------------
ui = "src/client/quantara_app/lib/core/widgets/quantara_ui.dart"
replace_once(
    ui,
    "import 'package:flutter/material.dart';\n",
    "import 'package:crypto_icons/crypto_icons.dart';\nimport 'package:flutter/material.dart';\n",
)
replace_once(
    ui,
    """    final color = brand?.$2 ?? _fallbackColor(base);
    final label = fallbackLabel ?? brand?.$1 ?? _fallbackText(base);
    return Semantics(
""",
    """    final color = brand?.$2 ?? _fallbackColor(base);
    final label = fallbackLabel ?? brand?.$1 ?? _fallbackText(base);
    final iconData = _iconFor(base);
    return Semantics(
""",
)
replace_once(
    ui,
    """          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: _foregroundFor(color),
              fontSize: size * (label.length > 1 ? 0.29 : 0.42),
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
""",
    """          alignment: Alignment.center,
          child: iconData == null || fallbackLabel != null
              ? Text(
                  label,
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: _foregroundFor(color),
                    fontSize: size * (label.length > 1 ? 0.29 : 0.42),
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                )
              : Icon(
                  iconData,
                  color: _foregroundFor(color),
                  size: size * 0.56,
                ),
""",
)
replace_once(
    ui,
    """  static String _fallbackText(String base) =>
      base.length <= 2 ? base : base.substring(0, 2);

  static Color _fallbackColor(String base) {
""",
    """  static String _fallbackText(String base) =>
      base.length <= 2 ? base : base.substring(0, 2);

  static IconData? _iconFor(String base) {
    try {
      return CryptoIconsExtension.fromSymbol(base);
    } on Object {
      return null;
    }
  }

  static Color _fallbackColor(String base) {
""",
)

# ---------------------------------------------------------------------------
# Profile identity and non-sensitive settings transfer.
# ---------------------------------------------------------------------------
page = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart"
replace_once(
    page,
    "import 'dart:async';\nimport 'dart:math' as math;\n",
    "import 'dart:async';\nimport 'dart:math' as math;\n\nimport 'package:flutter/services.dart';\n",
)
replace_once(
    page,
    "import '../data/signal_timeframe_priority.dart';\n",
    "import '../data/owner_alpha_settings_transfer.dart';\nimport '../data/signal_timeframe_priority.dart';\n",
)

exchange = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_exchange.dart"
replace_once(
    exchange,
    """  @override
  Widget build(BuildContext context) {
""",
    """  Future<void> _copySettingsBackup(BuildContext context) async {
    final persian = widget.locale.languageCode == 'fa';
    final payload = OwnerAlphaSettingsTransfer.encode(
      OwnerAlphaSettings(
        symbols: controller.symbols,
        capital: controller.capital,
        riskPercent: controller.riskPercent,
        strategy: controller.strategy,
        cadence: controller.cadence,
      ),
    );
    await Clipboard.setData(ClipboardData(text: payload));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persian
              ? 'نسخه پشتیبان تنظیمات در کلیپ‌بورد کپی شد. این متن شامل کلید API نیست.'
              : 'Settings backup copied to the clipboard. It contains no API credentials.',
        ),
      ),
    );
  }

  Future<void> _restoreSettingsBackup(BuildContext context) async {
    final persian = widget.locale.languageCode == 'fa';
    try {
      final clipboard = await Clipboard.getData('text/plain');
      final text = clipboard?.text;
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('empty clipboard');
      }
      final settings = OwnerAlphaSettingsTransfer.decode(text);
      final error = await controller.restoreSettings(settings);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ??
                (persian
                    ? 'واچ‌لیست و تنظیمات مدیریت سرمایه بازیابی شد.'
                    : 'Watchlist and risk settings were restored.'),
          ),
        ),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            persian
                ? 'متن معتبر پشتیبان Quantara در کلیپ‌بورد پیدا نشد.'
                : 'No valid Quantara settings backup was found in the clipboard.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
""",
)
replace_once(
    exchange,
    """              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [QuantaraColors.cyan, QuantaraColors.violet],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const SizedBox.square(
                  dimension: 58,
                  child: Icon(
                    Icons.person_rounded,
                    color: QuantaraColors.ink,
                    size: 32,
                  ),
                ),
              ),
""",
    """              const QuantaraBrandMark(size: 58),
""",
)
replace_once(
    exchange,
    """        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.settings,
""",
    """        ),
        const SizedBox(height: 16),
        SectionCard(
          accentColor: QuantaraColors.violet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_backup_restore_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.locale.languageCode == 'fa'
                          ? 'پشتیبان تنظیمات'
                          : 'Settings backup',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.locale.languageCode == 'fa'
                    ? 'واچ‌لیست، سرمایه فرضی، ریسک و سیاست سیگنال را بدون کلید API کپی یا بازیابی کن. برای انتقال از نسخه Preview به نسخه پایدار از این بخش استفاده کن.'
                    : 'Copy or restore watchlist, assumed capital, risk and signal policy without API credentials. Use this when moving from Preview to Stable.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copySettingsBackup(context),
                    icon: const Icon(Icons.copy_all_rounded),
                    label: Text(
                      widget.locale.languageCode == 'fa'
                          ? 'کپی پشتیبان'
                          : 'Copy backup',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _restoreSettingsBackup(context),
                    icon: const Icon(Icons.content_paste_go_rounded),
                    label: Text(
                      widget.locale.languageCode == 'fa'
                          ? 'بازیابی از کلیپ‌بورد'
                          : 'Restore from clipboard',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.settings,
""",
)

controller = "src/client/quantara_app/lib/features/owner_alpha/application/owner_alpha_controller.dart"
replace_once(
    controller,
    """  static String? _normalizeSymbol(String rawValue) {
""",
    """  Future<String?> restoreSettings(OwnerAlphaSettings settings) async {
    while (_activeScan != null) {
      await _activeScan!;
    }
    if (_disposed) return null;

    final normalized = settings.symbols
        .map(_normalizeSymbol)
        .whereType<String>()
        .toSet()
        .take(12)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return _t(
        'پشتیبان تنظیمات واچ‌لیست معتبر ندارد.',
        'The settings backup has no valid watchlist symbols.',
      );
    }
    _symbols = normalized;
    _selectedSymbol = normalized.contains(_selectedSymbol)
        ? _selectedSymbol
        : normalized.first;
    _capital = settings.capital.clamp(100, 100000000).toDouble();
    _riskPercent = settings.riskPercent.clamp(0.1, 2).toDouble();
    _strategy = settings.strategy;
    _cadence = settings.cadence;
    await _saveSettings();
    notifyListeners();
    await _requestScan(
      symbols: normalized,
      selectedSymbol: _selectedSymbol,
      selectedTimeframe: _selectedTimeframe,
    );
    return null;
  }

  static String? _normalizeSymbol(String rawValue) {
""",
)

write(
    "src/client/quantara_app/lib/features/owner_alpha/data/owner_alpha_settings_transfer.dart",
    r'''import 'dart:convert';

import '../domain/owner_alpha_models.dart';

abstract final class OwnerAlphaSettingsTransfer {
  static const marker = 'QUANTARA_SETTINGS_V1:';

  static String encode(OwnerAlphaSettings settings) {
    final payload = <String, Object>{
      'schema': 1,
      'symbols': settings.symbols,
      'capital': settings.capital,
      'riskPercent': settings.riskPercent,
      'strategy': settings.strategy.name,
      'cadence': settings.cadence.name,
    };
    return '$marker${jsonEncode(payload)}';
  }

  static OwnerAlphaSettings decode(String value) {
    final normalized = value.trim();
    if (!normalized.startsWith(marker)) {
      throw const FormatException('unsupported Quantara settings backup');
    }
    final decoded = jsonDecode(normalized.substring(marker.length));
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('invalid Quantara settings schema');
    }
    final rawSymbols = decoded['symbols'];
    final capital = decoded['capital'];
    final risk = decoded['riskPercent'];
    final strategyName = decoded['strategy'];
    final cadenceName = decoded['cadence'];
    if (rawSymbols is! List ||
        capital is! num ||
        risk is! num ||
        strategyName is! String ||
        cadenceName is! String) {
      throw const FormatException('invalid Quantara settings fields');
    }
    final symbols = rawSymbols
        .whereType<String>()
        .map((item) => item.trim().toUpperCase())
        .where((item) => RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(item))
        .toSet()
        .take(12)
        .toList(growable: false);
    final safeCapital = capital.toDouble();
    final safeRisk = risk.toDouble();
    if (symbols.isEmpty ||
        symbols.length != rawSymbols.length ||
        !safeCapital.isFinite ||
        safeCapital < 100 ||
        safeCapital > 100000000 ||
        !safeRisk.isFinite ||
        safeRisk < 0.1 ||
        safeRisk > 2) {
      throw const FormatException('unsafe Quantara settings values');
    }
    return OwnerAlphaSettings(
      symbols: symbols,
      capital: safeCapital,
      riskPercent: safeRisk,
      strategy: _enumByName(AnalysisStrategy.values, strategyName),
      cadence: _enumByName(SignalCadence.values, cadenceName),
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('unknown enum value: $name');
  }
}
''',
)

# ---------------------------------------------------------------------------
# Honest version/security copy.
# ---------------------------------------------------------------------------
strings = "src/client/quantara_app/lib/core/localization/app_strings.dart"
replace_once(
    strings,
    """  String get futureVersion => t('نسخه آینده', 'Future version');
  String get privateConnectionDescription => t(
    'کلید API در Android وارد یا ذخیره نمی‌شود. اتصال خصوصی بعداً فقط از Backend رمزنگاری‌شده و ابتدا به‌صورت Read-only اضافه می‌شود.',
    'API keys are never entered or stored on Android. Private access will later use an encrypted backend and begin as read-only.',
  );
""",
    """  String get futureVersion =>
      t('مدیریت از بخش ترید خودکار', 'Managed in Auto Trade');
  String get privateConnectionDescription => t(
    'اتصال حساب Bitunix و وضعیت اجرای محلی از بخش ترید خودکار مدیریت می‌شود. اتصال حساب به‌تنهایی هیچ سفارشی ثبت نمی‌کند.',
    'Bitunix account connection and local execution status are managed in Auto Trade. Connecting an account alone never places an order.',
  );
""",
)
replace_once(
    strings,
    """  String get securityDescription => t(
    'هیچ API Key یا مجوز معامله‌ای در اپ وجود ندارد. Quantara در این نسخه فقط مشاهده و تحلیل می‌کند.',
    'The app contains no API key or trading permission. This version of Quantara only observes and analyzes.',
  );
  String get about => t('درباره اپ', 'About');
  String get version => t('نسخه ۰٫۹٫۰ آزمایشی', 'Experimental version 0.9.0');
""",
    """  String get securityDescription => t(
    'در صورت اتصال Bitunix، اطلاعات اتصال فقط در Secure Storage اندروید نگه‌داری می‌شود و هرگز داخل پشتیبان تنظیمات قرار نمی‌گیرد. برداشت و انتقال در Quantara پشتیبانی نمی‌شود.',
    'When Bitunix is connected, credentials stay in Android Secure Storage and are never included in settings backups. Quantara does not support withdrawals or transfers.',
  );
  String get about => t('درباره اپ', 'About');
  String get version => t('نسخه ۱٫۰٫۰', 'Version 1.0.0');
""",
)

# ---------------------------------------------------------------------------
# Stable identity/signing. Preview builds keep .alpha; Stable fails closed.
# ---------------------------------------------------------------------------
write(
    "src/client/quantara_app/android/app/build.gradle.kts",
    r'''plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val quantaraStableRelease =
    (System.getenv("QUANTARA_STABLE_RELEASE") ?: "false").equals("true", ignoreCase = true)
val quantaraKeystorePath = System.getenv("QUANTARA_ANDROID_KEYSTORE_PATH")
val quantaraKeystorePassword = System.getenv("QUANTARA_ANDROID_KEYSTORE_PASSWORD")
val quantaraKeyAlias = System.getenv("QUANTARA_ANDROID_KEY_ALIAS")
val quantaraKeyPassword = System.getenv("QUANTARA_ANDROID_KEY_PASSWORD")

android {
    namespace = "com.quantara.quantara_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.quantara.quantara_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (quantaraStableRelease) {
            create("quantaraStable") {
                require(!quantaraKeystorePath.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEYSTORE_PATH is required for a Stable build."
                }
                require(!quantaraKeystorePassword.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEYSTORE_PASSWORD is required for a Stable build."
                }
                require(!quantaraKeyAlias.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEY_ALIAS is required for a Stable build."
                }
                require(!quantaraKeyPassword.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEY_PASSWORD is required for a Stable build."
                }
                storeFile = file(quantaraKeystorePath!!)
                storePassword = quantaraKeystorePassword
                keyAlias = quantaraKeyAlias
                keyPassword = quantaraKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (quantaraStableRelease) {
                signingConfig = signingConfigs.getByName("quantaraStable")
            } else {
                // Internal preview identity can coexist with Stable and is not update-compatible with it.
                applicationIdSuffix = ".alpha"
                versionNameSuffix = "-preview"
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}

flutter {
    source = "../.."
}
''',
)

write(
    ".github/workflows/android-stable-release.yml",
    r'''name: Android Stable release

on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: Stable GitHub release tag
        required: true
        default: v1.0.0
      publish_release:
        description: Publish the GitHub Release after validation
        required: true
        type: boolean
        default: true

permissions:
  contents: write

env:
  FLUTTER_VERSION: '3.44.8'

jobs:
  stable:
    name: Build permanently signed Stable APK
    runs-on: ubuntu-24.04
    timeout-minutes: 60
    environment: production
    steps:
      - name: Checkout main
        uses: actions/checkout@v4
        with:
          ref: main
          fetch-depth: 0

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - name: Decode owner-managed keystore
        shell: bash
        env:
          KEYSTORE_BASE64: ${{ secrets.QUANTARA_ANDROID_KEYSTORE_BASE64 }}
        run: |
          set -euo pipefail
          test -n "$KEYSTORE_BASE64"
          printf '%s' "$KEYSTORE_BASE64" | base64 --decode > "$RUNNER_TEMP/quantara-stable.jks"
          chmod 600 "$RUNNER_TEMP/quantara-stable.jks"

      - name: Validate source and tests
        working-directory: src/client/quantara_app
        run: |
          flutter pub get
          dart format --output=none --set-exit-if-changed lib test
          flutter analyze --fatal-infos
          flutter test

      - name: Build Stable APKs
        working-directory: src/client/quantara_app
        env:
          QUANTARA_STABLE_RELEASE: 'true'
          QUANTARA_ANDROID_KEYSTORE_PATH: ${{ runner.temp }}/quantara-stable.jks
          QUANTARA_ANDROID_KEYSTORE_PASSWORD: ${{ secrets.QUANTARA_ANDROID_KEYSTORE_PASSWORD }}
          QUANTARA_ANDROID_KEY_ALIAS: ${{ secrets.QUANTARA_ANDROID_KEY_ALIAS }}
          QUANTARA_ANDROID_KEY_PASSWORD: ${{ secrets.QUANTARA_ANDROID_KEY_PASSWORD }}
        run: |
          flutter build apk --release
          flutter build apk --release --split-per-abi

      - name: Verify Stable identity and signing
        working-directory: src/client/quantara_app
        shell: bash
        run: |
          set -euo pipefail
          apk="build/app/outputs/flutter-apk/app-release.apk"
          apkanalyzer_path="$(find "$ANDROID_SDK_ROOT/cmdline-tools" -type f -name apkanalyzer | sort -V | tail -n 1)"
          apksigner_path="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name apksigner | sort -V | tail -n 1)"
          zipalign_path="$(find "$ANDROID_SDK_ROOT/build-tools" -type f -name zipalign | sort -V | tail -n 1)"
          "$apkanalyzer_path" manifest application-id "$apk" | grep -Fxq 'com.quantara.quantara_app'
          ! "$apkanalyzer_path" manifest application-id "$apk" | grep -Fq '.alpha'
          "$apksigner_path" verify --verbose --print-certs "$apk" | tee stable-signing.txt
          "$zipalign_path" -c -P 16 -v 4 "$apk"
          sha256sum build/app/outputs/flutter-apk/*.apk | tee SHA256SUMS.txt

      - name: Upload signed candidate
        uses: actions/upload-artifact@v4
        with:
          name: quantara-android-stable-${{ inputs.release_tag }}
          path: |
            src/client/quantara_app/build/app/outputs/flutter-apk/app-release.apk
            src/client/quantara_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
            src/client/quantara_app/SHA256SUMS.txt
            src/client/quantara_app/stable-signing.txt
          retention-days: 90

      - name: Publish GitHub Release
        if: ${{ inputs.publish_release }}
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ inputs.release_tag }}
        shell: bash
        run: |
          set -euo pipefail
          test "$(git branch --show-current)" = "main"
          git tag "$TAG" "$GITHUB_SHA"
          git push origin "$TAG"
          gh release create "$TAG" \
            src/client/quantara_app/build/app/outputs/flutter-apk/app-release.apk#Quantara-Android-universal.apk \
            src/client/quantara_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk#Quantara-Android-arm64.apk \
            src/client/quantara_app/SHA256SUMS.txt \
            src/client/quantara_app/stable-signing.txt \
            --title "Quantara 1.0.0" \
            --notes "First stable Quantara source release. Analysis, monitoring and paper features are Stable; Local Live remains explicit opt-in Canary."
''',
)

# ---------------------------------------------------------------------------
# Windows/VS Code PWA runner and release notes.
# ---------------------------------------------------------------------------
write(
    "scripts/Run-QuantaraPwa.ps1",
    r'''[CmdletBinding()]
param(
    [switch]$ReleasePreview,
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$AppPath = Join-Path $RepositoryRoot 'src/client/quantara_app'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available in PATH. Install Flutter and run flutter doctor first.'
}

Push-Location $AppPath
try {
    flutter pub get
    if (-not $ReleasePreview) {
        Write-Host 'Starting Quantara in Chrome development mode...'
        flutter run -d chrome
        exit $LASTEXITCODE
    }

    Write-Host 'Building the release PWA...'
    flutter build web --release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $Python = Get-Command py -ErrorAction SilentlyContinue
    if ($Python) {
        Write-Host "Serving release PWA at http://localhost:$Port"
        py -m http.server $Port --directory build/web
        exit $LASTEXITCODE
    }
    $Python = Get-Command python -ErrorAction SilentlyContinue
    if ($Python) {
        Write-Host "Serving release PWA at http://localhost:$Port"
        python -m http.server $Port --directory build/web
        exit $LASTEXITCODE
    }
    throw 'Python was not found. Install Python or run: flutter run -d web-server --release'
}
finally {
    Pop-Location
}
''',
)

write(
    "docs/guides/pwa-windows-vscode.fa.md",
    r'''# اجرای Quantara PWA در ویندوز و VS Code

## پیش‌نیاز یک‌باره

1. Flutter Stable را نصب کن و مسیر `flutter/bin` را به PATH ویندوز اضافه کن.
2. Chrome و VS Code را نصب داشته باش.
3. در ترمینال VS Code از ریشه ریپو اجرا کن:

```powershell
flutter doctor
```

## سریع‌ترین حالت توسعه

از ریشه ریپو:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1
```

اسکریپت `flutter pub get` را اجرا می‌کند و برنامه را در Chrome بالا می‌آورد. تغییرات کد با Hot Reload قابل مشاهده است.

## تست خروجی واقعی PWA

برای تست نسخه Release، Service Worker و فایل‌های ساخته‌شده:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1 -ReleasePreview
```

بعد مرورگر را روی آدرس زیر باز کن:

```text
http://localhost:8080
```

برای پورت دیگر:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1 -ReleasePreview -Port 9090
```

فایل `index.html` را مستقیم با دوبارکلیک باز نکن؛ PWA و Service Worker برای رفتار درست باید از `localhost` یا HTTPS سرو شوند.

## اجرای دستی بدون اسکریپت

```powershell
cd .\src\client\quantara_app
flutter pub get
flutter run -d chrome
```

یا برای Release:

```powershell
flutter build web --release
py -m http.server 8080 --directory build/web
```

برای توقف سرور در ترمینال `Ctrl+C` را بزن.
''',
)

write(
    "docs/releases/v1.0.0.fa.md",
    r'''# Quantara 1.0.0 — نقطه پایدار اولیه

## وضعیت محصول

- تحلیل بازار عمومی، رادار، واچ‌لیست، صندوق سیگنال، نمایش نتیجه فرضی و Strategy Lab: پایدار اولیه.
- اتصال Bitunix و Local Live: همچنان Canary، خاموش به‌صورت پیش‌فرض و فقط با Start صریح.
- Server Auto، اجرای چندپوزیشن، Windows Native و آپدیتر داخل برنامه: برای نسخه‌های بعدی.

## ارتقا و حفظ داده

نسخه‌های Preview قبلی با package شناسه `.alpha` و کلید Debug موقتی CI ساخته شده‌اند؛ به همین دلیل Android آن‌ها را آپدیت یک برنامه واحد نمی‌داند. برای انتقال به اولین Stable یک نصب تمیز نهایی لازم است.

پیش از حذف Preview از مسیر «پروفایل > پشتیبان تنظیمات» متن پشتیبان را کپی کن. بعد از نصب Stable همان متن را در کلیپ‌بورد نگه دار و «بازیابی از کلیپ‌بورد» را بزن. کلیدهای API عمداً داخل این پشتیبان نیستند.

از نسخه Stable 1.0.0 به بعد package شناسه `com.quantara.quantara_app` و کلید امضای دائمی مالک ثابت می‌ماند؛ بنابراین APKهای بعدی روی نسخه قبلی نصب می‌شوند و SharedPreferences/Secure Storage حفظ می‌شود.

## چهار Secret لازم در GitHub Environment: production

- `QUANTARA_ANDROID_KEYSTORE_BASE64`
- `QUANTARA_ANDROID_KEYSTORE_PASSWORD`
- `QUANTARA_ANDROID_KEY_ALIAS`
- `QUANTARA_ANDROID_KEY_PASSWORD`

فایل keystore، رمزها و کلید خصوصی نباید در Git، Issue، چت یا Artifact عمومی قرار بگیرند. از keystore حداقل دو نسخه پشتیبان رمزگذاری‌شده و آفلاین نگه دار.

بعد از تنظیم Secrets، Workflow با نام `Android Stable release` را از شاخه `main` اجرا کن. Stable build در نبود هرکدام از Secrets عمداً Fail می‌شود و هرگز به Debug signing برنمی‌گردد.
''',
)

write(
    "src/client/quantara_app/THIRD_PARTY_NOTICES.md",
    """# Third-party notices

## CryptoIcons

Quantara uses the `crypto_icons` Flutter package and the cryptocurrency icon font originally created by Mirko Garozzo.

- Package license: MIT
- Original project: `mirgj/cryptocurrency-icons-font`

The icon font is bundled locally with the application and is not loaded from a network service at runtime.
""",
)

# ---------------------------------------------------------------------------
# Tests.
# ---------------------------------------------------------------------------
write(
    "src/client/quantara_app/test/owner_alpha_settings_transfer_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/owner_alpha_settings_transfer.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('round-trips non-sensitive owner settings', () {
    const settings = OwnerAlphaSettings(
      symbols: ['BTCUSDT', 'XRPUSDT'],
      capital: 800,
      riskPercent: 0.5,
      strategy: AnalysisStrategy.trendCandle,
      cadence: SignalCadence.active,
    );

    final encoded = OwnerAlphaSettingsTransfer.encode(settings);
    final decoded = OwnerAlphaSettingsTransfer.decode(encoded);

    expect(encoded, startsWith(OwnerAlphaSettingsTransfer.marker));
    expect(decoded.symbols, settings.symbols);
    expect(decoded.capital, settings.capital);
    expect(decoded.riskPercent, settings.riskPercent);
    expect(decoded.strategy, settings.strategy);
    expect(decoded.cadence, settings.cadence);
    expect(encoded.toLowerCase(), isNot(contains('api')));
    expect(encoded.toLowerCase(), isNot(contains('secret')));
  });

  test('rejects malformed or unsafe backups', () {
    expect(
      () => OwnerAlphaSettingsTransfer.decode('not-a-quantara-backup'),
      throwsFormatException,
    );
    expect(
      () => OwnerAlphaSettingsTransfer.decode(
        '${OwnerAlphaSettingsTransfer.marker}{"schema":1,"symbols":[],"capital":1,"riskPercent":20,"strategy":"structureZones","cadence":"balanced"}',
      ),
      throwsFormatException,
    );
  });
}
''',
)

symbol_test = "src/client/quantara_app/test/quantara_symbol_avatar_test.dart"
replace_once(
    symbol_test,
    "import 'package:flutter/material.dart';\n",
    "import 'package:crypto_icons/crypto_icons.dart';\nimport 'package:flutter/material.dart';\n",
)
replace_once(
    symbol_test,
    "    expect(find.text('₿'), findsOneWidget);\n",
    "    expect(find.byIcon(CryptoIcons.btc), findsOneWidget);\n",
)

# Remove one-shot machinery in the generated commit.
(ROOT / ".github/workflows/apply-v1-stabilization.yml").unlink(missing_ok=True)
Path(__file__).unlink(missing_ok=True)
