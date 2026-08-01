plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // P1b：Chaquopy 把 CPython 编译进 APK，提供进程内 Python 执行（对应 ChaquopyRunner）。
    // 必须在 plugins {} 块内声明并应用，Kotlin DSL 才能识别 chaquopy {} 扩展；
    // 版本 17.0.0 由 Maven Central 的 com.chaquo.python.gradle.plugin marker 解析。
    id("com.chaquo.python") version "17.0.0"
}

android {
    namespace = "com.example.evergreen_base"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.evergreen_base"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // P1b：Chaquopy 仅支持其已编译的 ABI。
        // 含 x86_64 以便在本机 x86_64 模拟器上运行验证（真机发布可只留 arm64-v8a 缩小体积）。
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
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

// P1b：Chaquopy 配置（进程内 Python 运行时）。
// 仅用标准库即可运行纯 Python 插件；若某插件需要第三方包（numpy / requests 等），
// 在此 pip { install("包名") } 声明，Chaquopy 会在构建期打包对应 wheel。
chaquopy {
    defaultConfig {
        version = "3.11"
        // 本机 buildPython（chaquopy 用它把 src/main/python 编译成 .pyc 打包进 APK）。
        // ⚠️ 缺失时 chaquopy 警告 "Couldn't find Python 3.11" 并整体跳过源打包
        // （2026-08-02 事故：pdf_translate.py 等未进 APK，运行时 getAssetPath 找不到）。
        buildPython = listOf("C:/Users/19389/AppData/Local/Programs/Python/Python311/python.exe")
        // pip 依赖已通过手动方式放入 src/main/python/（避免 buildPython 需求）。
        // pip {
        //     install("requests")
        // }
    }
    // Python 源目录默认 src/main/python（动态插件由 MethodChannel 从设备路径按需加载，无需打包进 APK）。
}
