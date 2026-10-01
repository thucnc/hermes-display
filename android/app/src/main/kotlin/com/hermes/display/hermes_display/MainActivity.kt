package com.hermes.display.hermes_display

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_START -> result.success(startMicService())
                    METHOD_STOP -> {
                        stopService(Intent(this, MicKeepAliveService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // The Dart mic stream dies with this activity's engine.
        if (isFinishing) {
            stopService(Intent(this, MicKeepAliveService::class.java))
        }
        super.onDestroy()
    }

    /** False when RECORD_AUDIO is missing or the OS refuses the service. */
    private fun startMicService(): Boolean {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val intent = Intent(this, MicKeepAliveService::class.java)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            true
        } catch (error: RuntimeException) {
            Log.w(TAG, "Mic service refused", error)
            false
        }
    }

    companion object {
        private const val TAG = "HermesDisplay"
        private const val CHANNEL = "hermes_display/mic_service"
        private const val METHOD_START = "start"
        private const val METHOD_STOP = "stop"
    }
}
