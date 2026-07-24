# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Gson / reflection used by some plugins
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Play Services / Google Sign-In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.api.client.** { *; }

# CameraX
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# ExoPlayer / media3 (video_player)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Geolocator / Play Services Location
-keep class com.google.android.gms.location.** { *; }

# Supabase / OkHttp / Kotlin serialization edges
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
