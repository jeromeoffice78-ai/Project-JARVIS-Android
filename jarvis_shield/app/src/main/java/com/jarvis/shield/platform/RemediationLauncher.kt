package com.jarvis.shield.platform

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import com.jarvis.shield.domain.model.RemediationAction

object RemediationLauncher {
    fun launch(
        activity: Activity,
        action: RemediationAction,
        packageName: String,
    ) {
        val packageUri = Uri.parse("package:$packageName")
        val intent = when (action) {
            RemediationAction.OPEN_APP_DETAILS -> Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                packageUri,
            )

            RemediationAction.UNINSTALL_APP -> Intent(
                Intent.ACTION_DELETE,
                packageUri,
            )

            RemediationAction.REVIEW_ACCESSIBILITY -> Intent(
                Settings.ACTION_ACCESSIBILITY_SETTINGS,
            )

            RemediationAction.REVIEW_NOTIFICATION_ACCESS -> Intent(
                Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS,
            )

            RemediationAction.REVIEW_DEVICE_ADMIN -> Intent(
                Settings.ACTION_SECURITY_SETTINGS,
            )

            RemediationAction.REVIEW_OVERLAY -> Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                packageUri,
            )

            RemediationAction.REVIEW_UNKNOWN_SOURCES -> Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                packageUri,
            )
        }

        try {
            activity.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            openFallbackSettings(activity)
        } catch (_: SecurityException) {
            openFallbackSettings(activity)
        }
    }

    private fun openFallbackSettings(activity: Activity) {
        try {
            activity.startActivity(Intent(Settings.ACTION_SETTINGS))
        } catch (_: Throwable) {
            Toast.makeText(
                activity,
                "Android settings could not be opened on this device.",
                Toast.LENGTH_LONG,
            ).show()
        }
    }
}
