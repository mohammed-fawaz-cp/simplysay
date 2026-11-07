plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.comlabs.simplysay"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.comlabs.simplysay"
        manifestPlaceholders["appAuthRedirectScheme"] = "com.comlabs.simplysay"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

tasks.matching { it.name.startsWith("compile") && it.name.contains("JavaWithJavac") }.configureEach {
    doFirst {
        val regFile = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        if (regFile.exists()) {
            val original = regFile.readText()
            if (!original.contains("NativeCallBridge")) {
                val updated = original.replace(
                    "public static void registerWith(@NonNull FlutterEngine flutterEngine) {",
                    "public static void registerWith(@NonNull FlutterEngine flutterEngine) {\n" +
                    "    try {\n" +
                    "      com.comlabs.simplysay.call.NativeCallBridge.registerWith(flutterEngine, com.comlabs.simplysay.MainApplication.getAppContext());\n" +
                    "    } catch (Exception e) {}\n"
                )
                regFile.writeText(updated)
            }
        }
    }
}

