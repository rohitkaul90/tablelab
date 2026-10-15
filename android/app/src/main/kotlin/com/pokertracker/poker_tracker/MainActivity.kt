package com.pokertracker.poker_tracker

import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            super.onCreate(savedInstanceState)
        } catch (e: Throwable) {
            // crash-issues-14: "Could not find 'libflutter.so' ... only found: []".
            // The Flutter engine's native libraries are absent from the INSTALLED
            // package (the Play ABI split never landed — a sideloaded/extracted
            // base APK, a device-transfer restore, or a broken install), so the
            // engine can't boot. Nothing in Dart ever runs, and the user sees an
            // instant crash loop. The shipped AAB carries every ABI (verified
            // against the v1.8.0 release artifact), so the only remedy is a
            // reinstall from Play — tell them that instead of crashing.
            //
            // Safe to swallow: FlutterActivity guards every later lifecycle hook
            // with stillAttachedForEvent(), which is false because the delegate
            // threw before isAttached was set — so an engine-less activity is a
            // supported (if degenerate) state.
            if (!isMissingNativeLibraryFailure(e)) throw e
            Log.e(TAG, "Flutter engine failed to load its native libraries", e)
            reportNonFatal(e)
            showReinstallDialog()
        }
    }

    /** True when the throwable chain is the engine failing to load libflutter.so / libapp.so. */
    private fun isMissingNativeLibraryFailure(root: Throwable): Boolean {
        var t: Throwable? = root
        var hops = 0
        while (t != null && hops < 8) {
            if (t is UnsatisfiedLinkError) return true
            // ReLinker's MissingLibraryException is obfuscated by R8, so match the class
            // name loosely and fall back to the (stable) message text.
            if (t.javaClass.simpleName == "MissingLibraryException") return true
            val msg = t.message ?: ""
            if (msg.contains("libflutter.so") ||
                msg.contains("libapp.so") ||
                msg.contains("Could not find 'lib")
            ) return true
            t = t.cause
            hops++
        }
        return false
    }

    /**
     * Mirrors the Dart side's `setCrashlyticsCollectionEnabled(!kDebugMode)` — debug builds
     * don't report. Reflection because the Crashlytics SDK reaches the app only transitively
     * through the firebase_crashlytics plugin (no compile-time dependency here); the class is
     * kept by `-keep class com.google.firebase.** { *; }` in proguard-rules.pro.
     */
    private fun reportNonFatal(e: Throwable) {
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (debuggable) return
        try {
            val cls = Class.forName("com.google.firebase.crashlytics.FirebaseCrashlytics")
            val instance = cls.getMethod("getInstance").invoke(null)
            cls.getMethod("log", String::class.java)
                .invoke(instance, "native-libs-missing guard: reinstall prompt shown")
            cls.getMethod("recordException", Throwable::class.java).invoke(instance, e)
        } catch (t: Throwable) {
            Log.w(TAG, "Crashlytics unavailable for non-fatal report", t)
        }
    }

    private fun showReinstallDialog() {
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("TableLab can't start")
            .setMessage(
                "This copy of TableLab is missing files it needs to run. That usually happens " +
                    "when the app was copied, backed up or restored from another device instead " +
                    "of installed from Google Play.\n\n" +
                    "Please uninstall TableLab and reinstall it from Google Play. Your sessions " +
                    "and hands are safe — they're stored in your account, not on this device."
            )
            .setPositiveButton("Open Google Play") { _, _ ->
                openPlayStore()
                finish()
            }
            .setNegativeButton("Close") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    private fun openPlayStore() {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
        try {
            startActivity(market)
        } catch (_: ActivityNotFoundException) {
            val web = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
            )
            try {
                startActivity(web)
            } catch (_: ActivityNotFoundException) {
                Log.w(TAG, "No activity can open the Play Store listing")
            }
        }
    }

    private companion object {
        const val TAG = "TableLab"
    }
}
