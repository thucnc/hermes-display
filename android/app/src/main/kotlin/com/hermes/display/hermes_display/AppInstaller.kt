package com.hermes.display.hermes_display

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/** Installed version and the system installer for downloaded APKs. */
class AppInstaller(private val activity: Activity) {
    fun version(): Map<String, Any> {
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode
        }
        return mapOf(KEY_CODE to code, KEY_NAME to (info.versionName ?: ""))
    }

    /** RESULT_STARTED, RESULT_PERMISSION (settings opened) or RESULT_FAILED. */
    fun install(path: String?): String {
        val apk = updateFile(path) ?: return RESULT_FAILED
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            return openUnknownSources()
        }
        val uri = FileProvider.getUriForFile(activity, authority(), apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, MIME_APK)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            activity.startActivity(intent)
            RESULT_STARTED
        } catch (error: ActivityNotFoundException) {
            Log.w(TAG, "No package installer", error)
            RESULT_FAILED
        }
    }

    private fun openUnknownSources(): String {
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}"),
        )
        return try {
            activity.startActivity(intent)
            RESULT_PERMISSION
        } catch (error: ActivityNotFoundException) {
            Log.w(TAG, "No unknown-sources settings", error)
            RESULT_FAILED
        }
    }

    /** The file only when it is an existing APK inside cache/updates. */
    private fun updateFile(path: String?): File? {
        if (path == null) {
            return null
        }
        val dir = File(activity.cacheDir, UPDATE_DIR).canonicalFile
        val file = File(path).canonicalFile
        if (file.parentFile != dir || !file.isFile || !file.name.endsWith(APK_SUFFIX)) {
            return null
        }
        return file
    }

    private fun authority() = "${activity.packageName}$AUTHORITY_SUFFIX"

    companion object {
        private const val TAG = "HermesUpdate"
        private const val KEY_CODE = "versionCode"
        private const val KEY_NAME = "versionName"
        private const val MIME_APK = "application/vnd.android.package-archive"
        private const val UPDATE_DIR = "updates"
        private const val APK_SUFFIX = ".apk"
        private const val AUTHORITY_SUFFIX = ".updates"
        const val RESULT_STARTED = "started"
        const val RESULT_PERMISSION = "permission"
        const val RESULT_FAILED = "failed"
    }
}
