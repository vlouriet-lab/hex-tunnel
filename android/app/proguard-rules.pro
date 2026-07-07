# Keep libbox classes used by JNI / reflection.
-keep class io.nekohasekai.libbox.** { *; }
-dontwarn io.nekohasekai.libbox.**

# Keep Flutter embedding and plugin registration.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep app service/channel classes referenced by Android manifest/runtime.
-keep class com.sota.hexdecensor.HexVpnService { *; }
-keep class com.sota.hexdecensor.MainActivity { *; }
-keep class com.sota.hexdecensor.SingBoxBridge { *; }
-keep class com.sota.hexdecensor.SingBoxController { *; }

# Flutter embedding may reference Play Core deferred-component classes.
# This app does not use deferred components, so suppress optional references.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Suppress annotation-only missing-class warnings from Tink / errorprone / javax.
-dontwarn com.google.crypto.tink.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**
