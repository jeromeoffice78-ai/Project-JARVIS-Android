package com.jarvis.shield.domain.model

enum class ThreatSeverity {
    LOW,
    MEDIUM,
    HIGH,
    CRITICAL,
}

enum class RemediationAction {
    OPEN_APP_DETAILS,
    UNINSTALL_APP,
    REVIEW_ACCESSIBILITY,
    REVIEW_NOTIFICATION_ACCESS,
    REVIEW_DEVICE_ADMIN,
    REVIEW_OVERLAY,
    REVIEW_UNKNOWN_SOURCES,
}

data class ThreatSignal(
    val id: String,
    val title: String,
    val detail: String,
    val weight: Int,
    val action: RemediationAction,
)

data class AppFinding(
    val appName: String,
    val packageName: String,
    val versionName: String?,
    val severity: ThreatSeverity,
    val riskScore: Int,
    val isSystemApp: Boolean,
    val installerPackage: String?,
    val signerSha256: String?,
    val apkSha256: String?,
    val firstInstallTimeEpochMs: Long,
    val lastUpdateTimeEpochMs: Long,
    val signals: List<ThreatSignal>,
)

data class SecurityScanResult(
    val startedAtEpochMs: Long,
    val completedAtEpochMs: Long,
    val scannedPackages: Int,
    val userPackages: Int,
    val findings: List<AppFinding>,
) {
    val criticalCount: Int
        get() = findings.count { it.severity == ThreatSeverity.CRITICAL }

    val highCount: Int
        get() = findings.count { it.severity == ThreatSeverity.HIGH }

    val mediumCount: Int
        get() = findings.count { it.severity == ThreatSeverity.MEDIUM }

    val durationMs: Long
        get() = (completedAtEpochMs - startedAtEpochMs).coerceAtLeast(0L)
}
