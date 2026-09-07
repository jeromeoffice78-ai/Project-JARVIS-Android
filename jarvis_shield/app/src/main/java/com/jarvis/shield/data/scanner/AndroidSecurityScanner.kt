package com.jarvis.shield.data.scanner

import android.Manifest
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import com.jarvis.shield.domain.model.AppFinding
import com.jarvis.shield.domain.model.SecurityScanResult
import com.jarvis.shield.domain.security.RiskEngine
import com.jarvis.shield.domain.security.RiskInput
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Singleton
class AndroidSecurityScanner @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val packageManager: PackageManager = context.packageManager
    private val appOpsManager: AppOpsManager = context.getSystemService(AppOpsManager::class.java)
    private val devicePolicyManager: DevicePolicyManager =
        context.getSystemService(DevicePolicyManager::class.java)

    suspend fun scan(): SecurityScanResult = withContext(Dispatchers.IO) {
        val startedAt = System.currentTimeMillis()
        val enabledAccessibilityPackages = readEnabledComponentPackages(
            settingName = "enabled_accessibility_services",
        )
        val enabledNotificationPackages = readEnabledComponentPackages(
            settingName = "enabled_notification_listeners",
        )
        val activeAdminPackages = runCatching {
            devicePolicyManager.activeAdmins.orEmpty().map { it.packageName }.toSet()
        }.getOrDefault(emptySet())

        val packages = getInstalledPackages()
        var userPackageCount = 0
        val findings = mutableListOf<AppFinding>()

        for (packageInfo in packages) {
            val applicationInfo = packageInfo.applicationInfo ?: continue
            if (packageInfo.packageName == context.packageName) continue

            val isSystemApp = applicationInfo.isSystemOrUpdatedSystemApp()
            if (!isSystemApp) userPackageCount += 1

            val grantedPermissions = grantedPermissions(packageInfo)
            val declaredPermissions = packageInfo.requestedPermissions.orEmpty().toSet()
            val services = packageInfo.services.orEmpty()
            val receivers = packageInfo.receivers.orEmpty()
            val installer = installerAssessment(packageInfo.packageName, isSystemApp)
            val appUid = applicationInfo.uid

            val accessibilityDeclared = services.any {
                it.permission == Manifest.permission.BIND_ACCESSIBILITY_SERVICE
            }
            val notificationListenerDeclared = services.any {
                it.permission == Manifest.permission.BIND_NOTIFICATION_LISTENER_SERVICE
            }
            val deviceAdminDeclared = receivers.any {
                it.permission == Manifest.permission.BIND_DEVICE_ADMIN
            }
            val overlayDeclared = Manifest.permission.SYSTEM_ALERT_WINDOW in declaredPermissions
            val packageInstallDeclared = Manifest.permission.REQUEST_INSTALL_PACKAGES in declaredPermissions

            val overlayAllowed = overlayDeclared && isAppOpAllowed(
                op = AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                uid = appUid,
                packageName = packageInfo.packageName,
            )
            val packageInstallAllowed = packageInstallDeclared && isAppOpAllowed(
                op = AppOpsManager.OPSTR_REQUEST_INSTALL_PACKAGES,
                uid = appUid,
                packageName = packageInfo.packageName,
            )

            val assessment = RiskEngine.assess(
                RiskInput(
                    isSystemApp = isSystemApp,
                    isSideloaded = installer.isSideloaded,
                    isAlternateInstaller = installer.isAlternateInstaller,
                    isDebuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0,
                    targetSdk = applicationInfo.targetSdkVersion,
                    communicationCapabilities = communicationCapabilities(grantedPermissions),
                    sensorCapabilities = sensorCapabilities(grantedPermissions),
                    personalDataCapabilities = personalDataCapabilities(grantedPermissions),
                    accessibilityDeclared = accessibilityDeclared,
                    accessibilityEnabled = packageInfo.packageName in enabledAccessibilityPackages,
                    notificationListenerDeclared = notificationListenerDeclared,
                    notificationListenerEnabled = packageInfo.packageName in enabledNotificationPackages,
                    deviceAdminDeclared = deviceAdminDeclared,
                    deviceAdminEnabled = packageInfo.packageName in activeAdminPackages,
                    overlayDeclared = overlayDeclared,
                    overlayAllowed = overlayAllowed,
                    packageInstallDeclared = packageInstallDeclared,
                    packageInstallAllowed = packageInstallAllowed,
                ),
            )

            if (assessment.score < MIN_FINDING_SCORE) continue

            findings += AppFinding(
                appName = safeApplicationLabel(applicationInfo, packageInfo.packageName),
                packageName = packageInfo.packageName,
                versionName = packageInfo.versionName,
                severity = assessment.severity,
                riskScore = assessment.score,
                isSystemApp = isSystemApp,
                installerPackage = installer.packageName,
                signerSha256 = signerSha256(packageInfo),
                apkSha256 = if (isSystemApp) null else fileSha256(applicationInfo.sourceDir),
                firstInstallTimeEpochMs = packageInfo.firstInstallTime,
                lastUpdateTimeEpochMs = packageInfo.lastUpdateTime,
                signals = assessment.signals,
            )
        }

        SecurityScanResult(
            startedAtEpochMs = startedAt,
            completedAtEpochMs = System.currentTimeMillis(),
            scannedPackages = packages.size,
            userPackages = userPackageCount,
            findings = findings.sortedWith(
                compareByDescending<AppFinding> { it.riskScore }
                    .thenBy { it.appName.lowercase() },
            ),
        )
    }

    private fun getInstalledPackages(): List<PackageInfo> {
        val flags = PackageManager.GET_PERMISSIONS or
            PackageManager.GET_SIGNING_CERTIFICATES or
            PackageManager.GET_SERVICES or
            PackageManager.GET_RECEIVERS

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getInstalledPackages(
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledPackages(flags)
        }
    }

    private fun grantedPermissions(packageInfo: PackageInfo): Set<String> {
        val permissions = packageInfo.requestedPermissions ?: return emptySet()
        val flags = packageInfo.requestedPermissionsFlags ?: return emptySet()
        val result = linkedSetOf<String>()

        permissions.forEachIndexed { index, permission ->
            val permissionFlags = flags.getOrNull(index) ?: 0
            if (permissionFlags and PackageInfo.REQUESTED_PERMISSION_GRANTED != 0) {
                result += permission
            }
        }
        return result
    }

    private fun communicationCapabilities(granted: Set<String>): Set<String> = buildSet {
        if (Manifest.permission.READ_SMS in granted) add("read SMS")
        if (Manifest.permission.RECEIVE_SMS in granted) add("receive SMS")
        if (Manifest.permission.SEND_SMS in granted) add("send SMS")
        if (Manifest.permission.READ_CALL_LOG in granted) add("read call log")
        if (Manifest.permission.WRITE_CALL_LOG in granted) add("write call log")
        if (Manifest.permission.READ_PHONE_STATE in granted) add("read phone state")
        if (Manifest.permission.READ_PHONE_NUMBERS in granted) add("read phone number")
        if (Manifest.permission.CALL_PHONE in granted) add("place calls")
        if (Manifest.permission.ANSWER_PHONE_CALLS in granted) add("answer calls")
    }

    private fun sensorCapabilities(granted: Set<String>): Set<String> = buildSet {
        if (Manifest.permission.RECORD_AUDIO in granted) add("microphone")
        if (Manifest.permission.CAMERA in granted) add("camera")
        if (Manifest.permission.ACCESS_FINE_LOCATION in granted) add("precise location")
        if (Manifest.permission.ACCESS_BACKGROUND_LOCATION in granted) add("background location")
        if (Manifest.permission.BODY_SENSORS in granted) add("body sensors")
    }

    private fun personalDataCapabilities(granted: Set<String>): Set<String> = buildSet {
        if (Manifest.permission.READ_CONTACTS in granted) add("read contacts")
        if (Manifest.permission.WRITE_CONTACTS in granted) add("modify contacts")
        if (Manifest.permission.READ_CALENDAR in granted) add("read calendar")
        if (Manifest.permission.WRITE_CALENDAR in granted) add("modify calendar")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (Manifest.permission.READ_MEDIA_IMAGES in granted) add("read photos")
            if (Manifest.permission.READ_MEDIA_VIDEO in granted) add("read videos")
            if (Manifest.permission.READ_MEDIA_AUDIO in granted) add("read audio")
        } else {
            @Suppress("DEPRECATION")
            if (Manifest.permission.READ_EXTERNAL_STORAGE in granted) add("read shared storage")
        }
    }

    private fun readEnabledComponentPackages(settingName: String): Set<String> {
        return runCatching {
            Settings.Secure.getString(context.contentResolver, settingName)
                .orEmpty()
                .split(':')
                .asSequence()
                .mapNotNull { value -> ComponentName.unflattenFromString(value) }
                .map { component -> component.packageName }
                .toSet()
        }.getOrDefault(emptySet())
    }

    private fun installerAssessment(
        packageName: String,
        isSystemApp: Boolean,
    ): InstallerAssessment {
        if (isSystemApp) {
            return InstallerAssessment(
                packageName = null,
                isSideloaded = false,
                isAlternateInstaller = false,
            )
        }

        val installerPackage = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName)
            }
        }.getOrNull()

        val isRecognizedStore = installerPackage in RECOGNIZED_STORES
        val isPackageInstaller = installerPackage in PACKAGE_INSTALLERS
        return InstallerAssessment(
            packageName = installerPackage,
            isSideloaded = installerPackage == null || isPackageInstaller,
            isAlternateInstaller = installerPackage != null && !isRecognizedStore && !isPackageInstaller,
        )
    }

    private fun isAppOpAllowed(
        op: String,
        uid: Int,
        packageName: String,
    ): Boolean {
        return runCatching {
            appOpsManager.checkOpNoThrow(op, uid, packageName) == AppOpsManager.MODE_ALLOWED
        }.getOrDefault(false)
    }

    private fun signerSha256(packageInfo: PackageInfo): String? {
        return runCatching {
            val signingInfo = packageInfo.signingInfo ?: return@runCatching null
            val signer = if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners.firstOrNull()
            } else {
                signingInfo.signingCertificateHistory.firstOrNull()
            } ?: return@runCatching null
            sha256Hex(signer.toByteArray())
        }.getOrNull()
    }

    private fun fileSha256(path: String?): String? {
        if (path.isNullOrBlank()) return null
        return runCatching {
            val digest = MessageDigest.getInstance("SHA-256")
            File(path).inputStream().buffered().use { input ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    digest.update(buffer, 0, read)
                }
            }
            digest.digest().toHex()
        }.getOrNull()
    }

    private fun safeApplicationLabel(
        applicationInfo: ApplicationInfo,
        fallback: String,
    ): String = runCatching {
        packageManager.getApplicationLabel(applicationInfo).toString().trim().ifBlank { fallback }
    }.getOrDefault(fallback)

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.toHex()
    }

    private fun ByteArray.toHex(): String = joinToString(separator = "") { byte ->
        "%02x".format(byte.toInt() and 0xff)
    }

    private fun ApplicationInfo.isSystemOrUpdatedSystemApp(): Boolean {
        return flags and ApplicationInfo.FLAG_SYSTEM != 0 ||
            flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0
    }

    private data class InstallerAssessment(
        val packageName: String?,
        val isSideloaded: Boolean,
        val isAlternateInstaller: Boolean,
    )

    private companion object {
        const val MIN_FINDING_SCORE = 15

        val RECOGNIZED_STORES = setOf(
            "com.android.vending",
            "com.amazon.venezia",
            "com.sec.android.app.samsungapps",
            "com.huawei.appmarket",
            "com.xiaomi.mipicks",
        )

        val PACKAGE_INSTALLERS = setOf(
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
        )
    }
}
