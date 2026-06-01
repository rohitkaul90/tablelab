# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core — Flutter's embedding (PlayStoreDeferredComponentManager) references
# these classes, but they aren't bundled and the app uses no deferred components.
# Without these rules R8 fails minifyRelease with "Missing class ... Compilation failed".
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Supabase / OkHttp
-keep class com.squareup.okhttp3.** { *; }
-dontwarn com.squareup.okhttp3.**

# Firebase / Crashlytics
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
