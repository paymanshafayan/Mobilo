plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mobilo.mobilo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (AAR metadata check fails
        // without it in release builds).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mobilo.mobilo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Stable sideload signing (android/app/mobilo-sideload.p12, committed).
    // Keeps every CI release APK signed identically -> updates over an
    // already-installed version succeed (the default debug key changes
    // per CI runner and caused "App not installed" on update).
    signingConfigs {
        create("mobilo") {
            storeFile = file("mobilo-sideload.p12")
            storePassword = "mobilo-sideload-2026"
            keyAlias = "mobilo"
            keyPassword = "mobilo-sideload-2026"
            storeType = "pkcs12"
        }
    }

    buildTypes {
        release {
            // Stable sideload signing key committed with the repo
            // (android/app/mobilo-sideload.p12). The GitHub Actions runner
            // regenerates a FRESH debug keystore on every run, so signing
            // release APKs with the debug key produced a different signature
            // per build: installing a new APK over an installed one failed
            // with a generic "App not installed" (INSTALL_FAILED_UPDATE_INCOMPATIBLE).
            // With one committed key every CI APK shares the same signature,
            // so updates install cleanly (also on Android 9).
            //
            // This key is ONLY for sideloading. For an app-store release
            // replace it with a private upload keystore + secrets
            // (see docs/HANDOFF.md section 6).
            signingConfig = signingConfigs.getByName("mobilo")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Core library desugaring (see isCoreLibraryDesugaringEnabled above).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
