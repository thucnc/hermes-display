package com.hermes.display.hermes_display

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Relaunches the kiosk after an OTA install replaced this package.
 * Android 10+ only allows the start while the app is the default home
 * app or holds "Display over other apps"; otherwise it is logged.
 */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        val launch = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        try {
            context.startActivity(launch)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Relaunch after update refused", error)
        }
    }

    companion object {
        private const val TAG = "HermesUpdate"
    }
}
