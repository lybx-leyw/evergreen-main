# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Dio + OkHttp
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# SQLite / Drift
-keep class org.sqlite.** { *; }

# Media Kit
-keep class com.alexmercerind.media_kit.** { *; }
-dontwarn com.alexmercerind.media_kit.**

# Path Provider
-keep class com.baseflow.** { *; }

# SharedPreferences
-keep class android.content.SharedPreferences { *; }

# ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# General
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
