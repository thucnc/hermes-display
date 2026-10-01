package com.hermes.display.hermes_display

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner

/**
 * Window brightness and lock-screen wake for [activity] only.
 *
 * Brightness uses WindowManager.LayoutParams.screenBrightness, so no
 * WRITE_SETTINGS permission is needed and the system value is untouched.
 */
class ScreenController(private val activity: Activity) {
    private var wakeLock: PowerManager.WakeLock? = null

    /** Null restores the system (auto or user) brightness. */
    fun setBrightness(level: Double?) {
        val window = activity.window
        val attrs = window.attributes
        attrs.screenBrightness =
            level?.toFloat() ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        window.attributes = attrs
    }

    /** Screen on, above the keyguard, existing task brought to front. */
    fun wake() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(true)
            activity.setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            activity.window.addFlags(LEGACY_WAKE_FLAGS)
        }
        pulseScreen()
        dismissInsecureKeyguard()
        bringToFront()
    }

    fun release() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(false)
            activity.setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            activity.window.clearFlags(LEGACY_WAKE_FLAGS or DISMISS_FLAG)
        }
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    /**
     * setTurnScreenOn only applies when the activity resumes; a stopped
     * activity (screen off) also needs a wake-up lock to light the panel.
     */
    @Suppress("DEPRECATION")
    private fun pulseScreen() {
        val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (power.isInteractive) {
            return
        }
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = power.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            WAKE_TAG,
        ).apply {
            setReferenceCounted(false)
            acquire(WAKE_PULSE_MS)
        }
    }

    /** Secure locks (PIN/pattern/face) stay; the app shows above them. */
    private fun dismissInsecureKeyguard() {
        val keyguard =
            activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!keyguard.isKeyguardLocked || keyguard.isKeyguardSecure) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            keyguard.requestDismissKeyguard(activity, null)
            return
        }
        @Suppress("DEPRECATION")
        activity.window.addFlags(DISMISS_FLAG)
    }

    /** singleTop + REORDER_TO_FRONT reuses this instance (onNewIntent). */
    private fun bringToFront() {
        val owner = activity as? LifecycleOwner
        if (owner?.lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED) == true) {
            return
        }
        val intent = Intent(activity, activity.javaClass).addFlags(
            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        try {
            activity.startActivity(intent)
        } catch (error: RuntimeException) {
            // Android 10+ may block background starts without the OEM
            // "pop-up in background" permission; the screen still lights.
            Log.w(TAG, "Bring to front refused", error)
        }
    }

    companion object {
        private const val TAG = "HermesDisplay"
        private const val WAKE_TAG = "HermesDisplay:screenWake"

        /** Long enough for the activity to resume and take over. */
        private const val WAKE_PULSE_MS = 10_000L

        @Suppress("DEPRECATION")
        private const val LEGACY_WAKE_FLAGS =
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON

        @Suppress("DEPRECATION")
        private const val DISMISS_FLAG = WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
    }
}
