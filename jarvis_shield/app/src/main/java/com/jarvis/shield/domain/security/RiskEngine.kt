package com.jarvis.shield.domain.security

import com.jarvis.shield.domain.model.RemediationAction
import com.jarvis.shield.domain.model.ThreatSeverity
import com.jarvis.shield.domain.model.ThreatSignal

data class RiskInput(
    val isSystemApp: Boolean,
    val isSideloaded: Boolean,
    val isAlternateInstaller: Boolean,
    val isDebuggable: Boolean,
    val targetSdk: Int,
    val communicationCapabilities: Set<String>,
    val sensorCapabilities: Set<String>,
    val personalDataCapabilities: Set<String>,
    val accessibilityDeclared: Boolean,
    val accessibilityEnabled: Boolean,
    val notificationListenerDeclared: Boolean,
    val notificationListenerEnabled: Boolean,
    val deviceAdminDeclared: Boolean,
    val deviceAdminEnabled: Boolean,
    val overlayDeclared: Boolean,
    val overlayAllowed: Boolean,
    val packageInstallDeclared: Boolean,
    val packageInstallAllowed: Boolean,
)

data class RiskAssessment(
    val score: Int,
    val severity: ThreatSeverity,
    val signals: List<ThreatSignal>,
)

object RiskEngine {
    private const val MAX_SCORE = 100

    fun assess(input: RiskInput): RiskAssessment {
        val signals = mutableListOf<ThreatSignal>()

        fun add(
            id: String,
            title: String,
            detail: String,
            weight: Int,
            action: RemediationAction,
        ) {
            if (weight <= 0) return
            signals += ThreatSignal(
                id = id,
                title = title,
                detail = detail,
                weight = weight,
                action = action,
            )
        }

        if (!input.isSystemApp) {
            when {
                input.isSideloaded -> add(
                    id = "install_source_sideloaded",
                    title = "Unknown or sideloaded install source",
                    detail = "This app was not identified as coming from a recognized app store.",
                    weight = 12,
                    action = RemediationAction.OPEN_APP_DETAILS,
                )

                input.isAlternateInstaller -> add(
                    id = "install_source_alternate",
                    title = "Alternate installer",
                    detail = "This app came from an installer other than the primary Google Play store.",
                    weight = 4,
                    action = RemediationAction.OPEN_APP_DETAILS,
                )
            }

            if (input.isDebuggable) {
                add(
                    id = "debuggable_release",
                    title = "Debuggable application",
                    detail = "Debuggable builds have a larger attack surface than normal production builds.",
                    weight = 8,
                    action = RemediationAction.OPEN_APP_DETAILS,
                )
            }

            if (input.targetSdk in 1..28) {
                add(
                    id = "legacy_target_sdk",
                    title = "Very old Android security target",
                    detail = "This app targets Android API ${input.targetSdk}, so it may not benefit from newer platform restrictions.",
                    weight = 8,
                    action = RemediationAction.OPEN_APP_DETAILS,
                )
            }

            if (input.communicationCapabilities.isNotEmpty()) {
                val count = input.communicationCapabilities.size
                add(
                    id = "communications_access",
                    title = "Phone, SMS, or call-log access",
                    detail = input.communicationCapabilities.sorted().joinToString(
                        prefix = "Granted capabilities: ",
                        separator = ", ",
                    ),
                    weight = (8 + (count * 4)).coerceAtMost(24),
                    action = RemediationAction.OPEN_APP_DETAILS,
                )
            }

            if (input.sensorCapabilities.isNotEmpty()) {
                val count = input.sensorCapabilities.size
                val weight = when {
                    count >= 3 -> 14
                    count == 2 -> 10
                    else -> 4
                }
                add(
                    id = "surveillance_sensors",
                    title = "Camera, microphone, location, or sensor access",
                    detail = input.sensorCapabilities.sorted().joinToString(
                        prefix = "Granted capabilities: ",
                        separator = ", ",
                    ),
                    weight = weight,
                    action = RemediationAction.OPEN_APP_DETAILS,
                )
            }

            if (input.personalDataCapabilities.isNotEmpty()) {
                val count = input.personalDataCapabilities.size
                add(
                    id = "personal_data_access",
                    title = "Personal-data access",
                    detail = input.personalDataCapabilities.sorted().joinToString(
                        prefix = "Granted capabilities: ",
                        separator = ", ",
                    ),
                    weight = (count * 3).coerceAtMost(12),
                    action = RemediationAction.OPEN_APP_DETAILS,
                )
            }
        }

        if (input.accessibilityEnabled) {
            add(
                id = "accessibility_enabled",
                title = "Accessibility control is enabled",
                detail = if (input.isSystemApp) {
                    "A system accessibility service is active. Confirm that you recognize why it is enabled."
                } else {
                    "This app can observe screen content and perform actions through Accessibility. This is frequently abused by banking trojans and remote-control scams."
                },
                weight = if (input.isSystemApp) 10 else 45,
                action = RemediationAction.REVIEW_ACCESSIBILITY,
            )
        } else if (input.accessibilityDeclared && !input.isSystemApp) {
            add(
                id = "accessibility_declared",
                title = "Accessibility-service capability",
                detail = "This app contains an accessibility service. It is not currently detected as enabled.",
                weight = 5,
                action = RemediationAction.REVIEW_ACCESSIBILITY,
            )
        }

        if (input.notificationListenerEnabled) {
            add(
                id = "notification_listener_enabled",
                title = "Notification access is enabled",
                detail = if (input.isSystemApp) {
                    "A system notification listener is active. Confirm that it is expected."
                } else {
                    "This app can read notifications, which may expose one-time codes, account alerts, and message content."
                },
                weight = if (input.isSystemApp) 8 else 30,
                action = RemediationAction.REVIEW_NOTIFICATION_ACCESS,
            )
        } else if (input.notificationListenerDeclared && !input.isSystemApp) {
            add(
                id = "notification_listener_declared",
                title = "Notification-listener capability",
                detail = "This app contains a notification listener. It is not currently detected as enabled.",
                weight = 4,
                action = RemediationAction.REVIEW_NOTIFICATION_ACCESS,
            )
        }

        if (input.deviceAdminEnabled) {
            add(
                id = "device_admin_enabled",
                title = "Device administrator is enabled",
                detail = if (input.isSystemApp) {
                    "A system device administrator is active. Confirm it belongs to your device-management setup."
                } else {
                    "This app has device-administrator privileges, which can make removal harder and can enforce device policies."
                },
                weight = if (input.isSystemApp) 10 else 40,
                action = RemediationAction.REVIEW_DEVICE_ADMIN,
            )
        } else if (input.deviceAdminDeclared && !input.isSystemApp) {
            add(
                id = "device_admin_declared",
                title = "Device-administrator capability",
                detail = "This app contains device-administrator components. They are not currently detected as active.",
                weight = 5,
                action = RemediationAction.REVIEW_DEVICE_ADMIN,
            )
        }

        if (!input.isSystemApp) {
            if (input.overlayAllowed) {
                add(
                    id = "overlay_allowed",
                    title = "Draw-over-other-apps access",
                    detail = "This app may place content over other apps. Malicious overlays can imitate sign-in or payment screens.",
                    weight = 25,
                    action = RemediationAction.REVIEW_OVERLAY,
                )
            } else if (input.overlayDeclared) {
                add(
                    id = "overlay_declared",
                    title = "Overlay capability",
                    detail = "This app requests the ability to draw over other apps. The scanner could not confirm that the special access is currently allowed.",
                    weight = 7,
                    action = RemediationAction.REVIEW_OVERLAY,
                )
            }

            if (input.packageInstallAllowed) {
                add(
                    id = "package_install_allowed",
                    title = "Can install unknown apps",
                    detail = "This app is allowed to request installation of APK files. Scam and dropper apps can abuse this capability.",
                    weight = 20,
                    action = RemediationAction.REVIEW_UNKNOWN_SOURCES,
                )
            } else if (input.packageInstallDeclared) {
                add(
                    id = "package_install_declared",
                    title = "APK-install capability",
                    detail = "This app requests permission to install packages. The scanner could not confirm that the special access is currently allowed.",
                    weight = 7,
                    action = RemediationAction.REVIEW_UNKNOWN_SOURCES,
                )
            }

            if (input.accessibilityEnabled && input.notificationListenerEnabled) {
                add(
                    id = "combo_accessibility_notifications",
                    title = "High-risk interception combination",
                    detail = "Accessibility control and notification access are both enabled. Together they can expose screen content, messages, and one-time codes.",
                    weight = 25,
                    action = RemediationAction.REVIEW_ACCESSIBILITY,
                )
            }

            if (input.accessibilityEnabled && input.overlayAllowed) {
                add(
                    id = "combo_accessibility_overlay",
                    title = "High-risk control-and-overlay combination",
                    detail = "Accessibility control and overlay access are both enabled, a combination commonly associated with credential-stealing behavior.",
                    weight = 30,
                    action = RemediationAction.REVIEW_ACCESSIBILITY,
                )
            }

            if (input.accessibilityEnabled && input.sensorCapabilities.isNotEmpty()) {
                add(
                    id = "combo_accessibility_sensors",
                    title = "Screen control plus surveillance sensors",
                    detail = "Accessibility control is enabled while camera, microphone, location, or sensor access is also granted.",
                    weight = 20,
                    action = RemediationAction.REVIEW_ACCESSIBILITY,
                )
            }

            if (input.deviceAdminEnabled && input.isSideloaded) {
                add(
                    id = "combo_admin_sideload",
                    title = "Sideloaded app with device-admin control",
                    detail = "An app from an unrecognized source has device-administrator privileges. Review this immediately if you did not intentionally set it up.",
                    weight = 20,
                    action = RemediationAction.REVIEW_DEVICE_ADMIN,
                )
            }

            if (input.packageInstallAllowed && input.isSideloaded) {
                add(
                    id = "combo_installer_sideload",
                    title = "Sideloaded app can install more apps",
                    detail = "This app came from an unrecognized source and can request installation of additional APKs.",
                    weight = 15,
                    action = RemediationAction.REVIEW_UNKNOWN_SOURCES,
                )
            }
        }

        val score = signals.sumOf { it.weight }.coerceIn(0, MAX_SCORE)
        val severity = when {
            score >= 80 -> ThreatSeverity.CRITICAL
            score >= 55 -> ThreatSeverity.HIGH
            score >= 30 -> ThreatSeverity.MEDIUM
            else -> ThreatSeverity.LOW
        }

        return RiskAssessment(
            score = score,
            severity = severity,
            signals = signals.sortedByDescending { it.weight },
        )
    }
}
