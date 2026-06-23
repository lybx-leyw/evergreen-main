pluginManagement {
    val flutterSdkPath = System.getenv("FLUTTER_ROOT")
        ?: run {
            val localProps = java.io.File(rootDir.absolutePath + "/local.properties")
            if (localProps.exists()) {
                localProps.readLines().firstOrNull { it.startsWith("flutter.sdk=") }
                    ?.substringAfter("=")?.trim()
            } else null
        }
    val settings = settings
    if (flutterSdkPath != null) {
        includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    }

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
