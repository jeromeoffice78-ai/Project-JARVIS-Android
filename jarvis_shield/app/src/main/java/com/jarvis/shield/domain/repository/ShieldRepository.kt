package com.jarvis.shield.domain.repository

import com.jarvis.shield.domain.model.ScanSummary
import kotlinx.coroutines.flow.Flow

interface ShieldRepository {
    val monitoringEnabled: Flow<Boolean>
    val scanCount: Flow<Int>
    val latestScan: Flow<ScanSummary?>

    suspend fun setMonitoringEnabled(enabled: Boolean)
    suspend fun recordFoundationVerification()
}
