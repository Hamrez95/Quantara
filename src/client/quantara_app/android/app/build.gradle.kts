plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val quantaraStableRelease =
    (System.getenv("QUANTARA_STABLE_RELEASE") ?: "false").equals("true", ignoreCase = true)
val quantaraPreviewRelease =
    (System.getenv("QUANTARA_PREVIEW_RELEASE") ?: "false").equals("true", ignoreCase = true)
val quantaraUnsignedCandidate =
    (System.getenv("QUANTARA_UNSIGNED_CANDIDATE") ?: "false").equals("true", ignoreCase = true)
require(
    listOf(quantaraStableRelease, quantaraPreviewRelease, quantaraUnsignedCandidate)
        .count { it } <= 1
) {
    "A build can select only one of Stable, Preview, or Unsigned Candidate."
}

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
        if (quantaraPreviewRelease) {
            create("quantaraPreview") {
                require(!quantaraKeystorePath.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEYSTORE_PATH is required for a Preview build."
                }
                require(!quantaraKeystorePassword.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEYSTORE_PASSWORD is required for a Preview build."
                }
                require(!quantaraKeyAlias.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEY_ALIAS is required for a Preview build."
                }
                require(!quantaraKeyPassword.isNullOrBlank()) {
                    "QUANTARA_ANDROID_KEY_PASSWORD is required for a Preview build."
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
            when {
                quantaraStableRelease -> {
                    signingConfig = signingConfigs.getByName("quantaraStable")
                }
                quantaraPreviewRelease -> {
                    applicationIdSuffix = ".alpha"
                    versionNameSuffix = "-preview"
                    signingConfig = signingConfigs.getByName("quantaraPreview")
                }
                quantaraUnsignedCandidate -> {
                    // Internal CI transport only. This APK is deliberately
                    // unsigned and must never be distributed until it is
                    // signed with the owner-controlled Preview keystore.
                    applicationIdSuffix = ".alpha"
                    versionNameSuffix = "-preview"
                    signingConfig = null
                }
                else -> {
                    throw GradleException(
                        "Release APK signing is fail-closed. Set QUANTARA_PREVIEW_RELEASE=true " +
                            "with the owner-controlled Preview keystore, QUANTARA_STABLE_RELEASE=true " +
                            "with the Stable keystore, or QUANTARA_UNSIGNED_CANDIDATE=true only for " +
                            "an internal offline-signing candidate. Runner-local debug signing is forbidden."
                    )
                }
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