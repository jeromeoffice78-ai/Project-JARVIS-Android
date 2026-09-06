package com.jarvis.shield.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShieldScreen(
    state: ShieldUiState,
    onMonitoringChanged: (Boolean) -> Unit,
    onVerifyFoundation: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(title = { Text("JARVIS Shield") })
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .padding(20.dp)
                .fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = "Anti-scam and anti-spyware protection",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = "Phase 1 establishes the secure Android foundation, local database, preferences, dependency injection, and production app shell. The active malware and spyware scanner is installed in Phase 2 after you approve this foundation.",
                style = MaterialTheme.typography.bodyMedium,
            )

            Card(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(18.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Protection monitoring", fontWeight = FontWeight.SemiBold)
                        Text(
                            if (state.monitoringEnabled) "Enabled" else "Disabled",
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Switch(
                        checked = state.monitoringEnabled,
                        onCheckedChange = onMonitoringChanged,
                    )
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Text("Foundation status", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    Text("Local verification records: ${state.verificationCount}")
                    Text(
                        text = state.latestVerification?.status ?: "Not verified yet",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Spacer(Modifier.height(14.dp))
                    Button(
                        onClick = onVerifyFoundation,
                        enabled = !state.isWorking,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (state.isWorking) "VERIFYING…" else "VERIFY PHASE 1 FOUNDATION")
                    }
                }
            }

            if (state.errorMessage != null) {
                Text(
                    text = state.errorMessage,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            Text(
                text = "Important: normal Android apps cannot silently remove other apps or guarantee detection of every threat. JARVIS Shield will identify high-risk apps and settings, then use Android's secure removal and settings flows with your approval.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 800, heightDp = 1280)
@Composable
private fun ShieldScreenPreview() {
    MaterialTheme {
        ShieldScreen(
            state = ShieldUiState(
                monitoringEnabled = true,
                verificationCount = 2,
            ),
            onMonitoringChanged = {},
            onVerifyFoundation = {},
        )
    }
}
