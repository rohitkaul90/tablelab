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

    private var reinstallDialog: AlertDialog? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            super.onCreate(savedInstanceState)
        } catch (e: Throwable) {
            // crash-issues-14: "Could not find 'libflutter.so'. Looked for: [...],
            // but only found: []". The INSTALLED package has no native-library
            // directory at all — the Play ABI split never landed (a sideloaded /
            // extracted base APK, a device-transfer restore, a broken install), so
            // the engine can't boot, no Dart ever runs, and the user sees an
            // instant crash loop. The shipped AAB carries every ABI (verified
            // against the v1.8.0 release artifact), so the only remedy is a
            // reinstall from Play — tell them that instead of crashing.
            //
            // Deliberately NARROW (code-review on PR #86): only the "no libs at
            // all" install-integrity case is swallowed. A package that HAS libs
            // but can't load them (wrong ABI, missing JNI symbol, 16 KB
            // alignment, a bad release build) must stay a FATAL so Crashlytics
            // still registers a crash spike and the rollout halt still fires.
            //
            // Safe to swallow only while the engine never constructed:
            // FlutterActivityAndFragmentDelegate sets isAttached AFTER
            // setUpFlutterEngine(), so every later lifecycle hook is skipped by
            // stillAttachedForEvent(). If an engine exists the invariant is gone
            // and we rethrow.
            if (flutterEngine != null || !isNativeLibsAbsentFailure(e)) throw e
            Log.e(TAG, "Installed package has no native libraries; prompting reinstall", e)
            reportNonFatal(e)
            showReinstallDialog()
        }
    }

    override fun onDestroy() {
        reinstallDialog?.dismiss()
        reinstallDialog = null
        super.onDestroy()
    }

    /**
     * True only for ReLinker's "could not find libflutter.so ... but only found: []"
     * — i.e. the APK set contains NO lib/<abi>/ directory for any ABI. ReLinker's
     * MissingLibraryException class is R8-obfuscated in release, so match the
     * (stable) message text, not the class.
     */
    private fun isNativeLibsAbsentFailure(root: Throwable): Boolean {
        var t: Throwable? = root
        var hops = 0
        while (t != null && hops < 8) {
            val msg = t.message ?: ""
            if (msg.contains("libflutter.so") && msg.contains("only found: []")) return true
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
     *
     * Known undercount: Crashlytics uploads a session's non-fatals on the NEXT launch, so a
     * user who uninstalls before relaunching never sends this one. The dialog therefore asks
     * for an install from Play (an in-place update keeps the data dir), not an uninstall.
     */
    private fun reportNonFatal(e: Throwable) {
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (debuggable) return
        try {
            val cls = Class.forName("com.google.firebase.crashlytics.FirebaseCrashlytics")
            val instance = cls.getMethod("getInstance").invoke(null)
            cls.getMethod("log", String::class.java)
                .invoke(instance, "native-libs-absent guard: reinstall prompt shown")
            cls.getMethod("recordException", Throwable::class.java).invoke(instance, e)
        } catch (t: Throwable) {
            Log.w(TAG, "Crashlytics unavailable for non-fatal report", t)
        }
    }

    private fun showReinstallDialog() {
        reinstallDialog = AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("TableLab can't start")
            .setMessage(
                "This copy of TableLab is missing files it needs to run. That usually happens " +
                    "when the app was copied, backed up or restored from another device instead " +
                    "of installed from Google Play.\n\n" +
                    "Please install TableLab again from Google Play. Your sessions and hands " +
                    "are safe — they're stored in your account, not on this device."
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
