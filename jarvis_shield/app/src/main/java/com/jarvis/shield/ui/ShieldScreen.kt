package com.jarvis.shield.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.weight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.jarvis.shield.domain.model.AppFinding
import com.jarvis.shield.domain.model.RemediationAction
import com.jarvis.shield.domain.model.SecurityScanResult
import com.jarvis.shield.domain.model.ThreatSeverity
import com.jarvis.shield.domain.model.ThreatSignal
import java.text.DateFormat
import java.util.Date

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShieldScreen(
    state: ShieldUiState,
    onMonitoringChanged: (Boolean) -> Unit,
    onScanNow: () -> Unit,
    onRemediation: (RemediationAction, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("JARVIS Shield")
                        Text(
                            text = "Android threat & scam defense",
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                ProtectionCard(
                    monitoringEnabled = state.monitoringEnabled,
                    onMonitoringChanged = onMonitoringChanged,
                )
            }

            item {
                ScanControlCard(
                    isScanning = state.isScanning,
                    scanCount = state.scanCount,
                    latestStatus = state.latestScan?.status,
                    onScanNow = onScanNow,
                )
            }

            if (state.errorMessage != null) {
                item {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer,
                        ),
                    ) {
                        Column(Modifier.padding(16.dp)) {
                            Text(
                                text = "Scan error",
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                            )
                            Spacer(Modifier.height(6.dp))
                            Text(
                                text = state.errorMessage,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                            )
                        }
                    }
                }
            }

            state.currentResult?.let { result ->
                item {
                    ScanSummaryCard(result)
                }

                if (result.findings.isEmpty()) {
                    item {
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(18.dp)) {
                                Text(
                                    text = "No strong risk indicators found",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Bold,
                                )
                                Spacer(Modifier.height(6.dp))
                                Text(
                                    text = "This heuristic scan did not identify installed apps that crossed the review threshold. This is not a guarantee that the device is malware-free.",
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            }
                        }
                    }
                } else {
                    item {
                        Text(
                            text = "Apps requiring review",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = "A finding means the app has risky capabilities or settings. It is not proof that the app is malicious.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }

                    items(
                        items = result.findings,
                        key = { finding -> finding.packageName },
                    ) { finding ->
                        FindingCard(
                            finding = finding,
                            onRemediation = onRemediation,
                        )
                    }
                }
            }

            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            text = "What this scan checks",
                            fontWeight = FontWeight.Bold,
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = "Installed-app inventory, app source, granted sensitive permissions, enabled Accessibility services, notification access, device-admin control, overlay access, unknown-app installation capability, signing-certificate SHA-256, and base-APK SHA-256 for reviewed user apps.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Android does not allow a normal security app to silently delete arbitrary apps or read every app's private data. Removal therefore goes through Android's protected confirmation screens.",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ProtectionCard(
    monitoringEnabled: Boolean,
    onMonitoringChanged: (Boolean) -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Protection preference",
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = if (monitoringEnabled) "Enabled" else "Disabled",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Switch(
                checked = monitoringEnabled,
                onCheckedChange = onMonitoringChanged,
            )
        }
    }
}

@Composable
private fun ScanControlCard(
    isScanning: Boolean,
    scanCount: Int,
    latestStatus: String?,
    onScanNow: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp)) {
            Text(
                text = "Device security scan",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = "Completed scans: $scanCount",
                style = MaterialTheme.typography.bodySmall,
            )
            if (!latestStatus.isNullOrBlank()) {
                Text(
                    text = "Latest: ${latestStatus.replace('_', ' ')}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Spacer(Modifier.height(12.dp))
            if (isScanning) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(10.dp))
                Text(
                    text = "Inspecting installed apps and high-risk Android access…",
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = onScanNow,
                enabled = !isScanning,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (isScanning) "SCANNING…" else "SCAN NOW")
            }
        }
    }
}

@Composable
private fun ScanSummaryCard(result: SecurityScanResult) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp)) {
            Text(
                text = "Scan results",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(8.dp))
            Text("Packages inspected: ${result.scannedPackages}")
            Text("User-installed packages: ${result.userPackages}")
            Text("Apps flagged for review: ${result.findings.size}")
            Text("Critical: ${result.criticalCount}  •  High: ${result.highCount}  •  Medium: ${result.mediumCount}")
            Text(
                text = "Completed ${formatEpoch(result.completedAtEpochMs)} in ${result.durationMs} ms",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun FindingCard(
    finding: AppFinding,
    onRemediation: (RemediationAction, String) -> Unit,
) {
    val containerColor = when (finding.severity) {
        ThreatSeverity.CRITICAL -> MaterialTheme.colorScheme.errorContainer
        ThreatSeverity.HIGH -> MaterialTheme.colorScheme.tertiaryContainer
        ThreatSeverity.MEDIUM -> MaterialTheme.colorScheme.secondaryContainer
        ThreatSeverity.LOW -> MaterialTheme.colorScheme.surfaceVariant
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = finding.appName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = finding.packageName,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Text(
                    text = "${finding.severity.name} ${finding.riskScore}/100",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                )
            }

            Spacer(Modifier.height(10.dp))
            finding.signals.forEachIndexed { index, signal ->
                if (index > 0) {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                }
                Text(
                    text = signal.title,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = signal.detail,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Spacer(Modifier.height(12.dp))
            Text(
                text = "Installer: ${finding.installerPackage ?: "unknown / preloaded"}",
                style = MaterialTheme.typography.labelSmall,
            )
            finding.signerSha256?.let {
                Text(
                    text = "Signer SHA-256: ${compactHash(it)}",
                    style = MaterialTheme.typography.labelSmall,
                )
            }
            finding.apkSha256?.let {
                Text(
                    text = "APK SHA-256: ${compactHash(it)}",
                    style = MaterialTheme.typography.labelSmall,
                )
            }

            Spacer(Modifier.height(12.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = {
                        onRemediation(
                            RemediationAction.OPEN_APP_DETAILS,
                            finding.packageName,
                        )
                    },
                ) {
                    Text("App details")
                }

                finding.signals
                    .map { it.action }
                    .filter { it != RemediationAction.OPEN_APP_DETAILS }
                    .distinct()
                    .forEach { action ->
                        OutlinedButton(
                            onClick = { onRemediation(action, finding.packageName) },
                        ) {
                            Text(actionLabel(action))
                        }
                    }

                if (!finding.isSystemApp) {
                    FilledTonalButton(
                        onClick = {
                            onRemediation(
                                RemediationAction.UNINSTALL_APP,
                                finding.packageName,
                            )
                        },
                    ) {
                        Text("Remove app")
                    }
                }
            }
        }
    }
}

private fun actionLabel(action: RemediationAction): String = when (action) {
    RemediationAction.OPEN_APP_DETAILS -> "App details"
    RemediationAction.UNINSTALL_APP -> "Remove app"
    RemediationAction.REVIEW_ACCESSIBILITY -> "Accessibility"
    RemediationAction.REVIEW_NOTIFICATION_ACCESS -> "Notification access"
    RemediationAction.REVIEW_DEVICE_ADMIN -> "Device admin"
    RemediationAction.REVIEW_OVERLAY -> "Overlay access"
    RemediationAction.REVIEW_UNKNOWN_SOURCES -> "Install unknown apps"
}

private fun compactHash(hash: String): String {
    if (hash.length <= 24) return hash
    return "${hash.take(12)}…${hash.takeLast(12)}"
}

private fun formatEpoch(epochMs: Long): String {
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
        .format(Date(epochMs))
}

@Preview(showBackground = true, widthDp = 800, heightDp = 1280)
@Composable
private fun ShieldScreenPreview() {
    val now = remember { System.currentTimeMillis() }
    MaterialTheme {
        ShieldScreen(
            state = ShieldUiState(
                monitoringEnabled = true,
                scanCount = 3,
                currentResult = SecurityScanResult(
                    startedAtEpochMs = now - 1_500,
                    completedAtEpochMs = now,
                    scannedPackages = 74,
                    userPackages = 31,
                    findings = listOf(
                        AppFinding(
                            appName = "Example Remote Tool",
                            packageName = "example.remote.tool",
                            versionName = "2.4",
                            severity = ThreatSeverity.CRITICAL,
                            riskScore = 92,
                            isSystemApp = false,
                            installerPackage = null,
                            signerSha256 = "a".repeat(64),
                            apkSha256 = "b".repeat(64),
                            firstInstallTimeEpochMs = now - 86_400_000,
                            lastUpdateTimeEpochMs = now - 86_400_000,
                            signals = listOf(
                                ThreatSignal(
                                    id = "accessibility_enabled",
                                    title = "Accessibility control is enabled",
                                    detail = "This app can observe screen content and perform actions.",
                                    weight = 45,
                                    action = RemediationAction.REVIEW_ACCESSIBILITY,
                                ),
                                ThreatSignal(
                                    id = "notification_listener_enabled",
                                    title = "Notification access is enabled",
                                    detail = "This app can read notification content.",
                                    weight = 30,
                                    action = RemediationAction.REVIEW_NOTIFICATION_ACCESS,
                                ),
                            ),
                        ),
                    ),
                ),
            ),
            onMonitoringChanged = {},
            onScanNow = {},
            onRemediation = { _, _ -> },
        )
    }
}
