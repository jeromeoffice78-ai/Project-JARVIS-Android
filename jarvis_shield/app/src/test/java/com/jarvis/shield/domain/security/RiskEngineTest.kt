package com.jarvis.shield.domain.security

import com.jarvis.shield.domain.model.ThreatSeverity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RiskEngineTest {
    @Test
    fun accessibilityAndNotificationAccessBecomeCritical() {
        val result = RiskEngine.assess(
            baseInput().copy(
                accessibilityDeclared = true,
                accessibilityEnabled = true,
                notificationListenerDeclared = true,
                notificationListenerEnabled = true,
            ),
        )

        assertEquals(ThreatSeverity.CRITICAL, result.severity)
        assertEquals(100, result.score)
        assertTrue(result.signals.any { it.id == "combo_accessibility_notifications" })
    }

    @Test
    fun sideloadedDeviceAdministratorIsHighRisk() {
        val result = RiskEngine.assess(
            baseInput().copy(
                isSideloaded = true,
                deviceAdminDeclared = true,
                deviceAdminEnabled = true,
            ),
        )

        assertEquals(ThreatSeverity.HIGH, result.severity)
        assertEquals(72, result.score)
        assertTrue(result.signals.any { it.id == "combo_admin_sideload" })
    }

    @Test
    fun ordinaryCameraPermissionAloneRemainsLowRisk() {
        val result = RiskEngine.assess(
            baseInput().copy(
                sensorCapabilities = setOf("camera"),
            ),
        )

        assertEquals(ThreatSeverity.LOW, result.severity)
        assertEquals(4, result.score)
    }

    private fun baseInput() = RiskInput(
        isSystemApp = false,
        isSideloaded = false,
        isAlternateInstaller = false,
        isDebuggable = false,
        targetSdk = 35,
        communicationCapabilities = emptySet(),
        sensorCapabilities = emptySet(),
        personalDataCapabilities = emptySet(),
        accessibilityDeclared = false,
        accessibilityEnabled = false,
        notificationListenerDeclared = false,
        notificationListenerEnabled = false,
        deviceAdminDeclared = false,
        deviceAdminEnabled = false,
        overlayDeclared = false,
        overlayAllowed = false,
        packageInstallDeclared = false,
        packageInstallAllowed = false,
    )
}
