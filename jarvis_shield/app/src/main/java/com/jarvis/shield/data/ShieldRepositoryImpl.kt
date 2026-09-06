package com.jarvis.shield.data

import com.jarvis.shield.data.local.ScanEventDao
import com.jarvis.shield.data.local.ScanEventEntity
import com.jarvis.shield.data.preferences.ShieldPreferences
import com.jarvis.shield.domain.model.ScanSummary
import com.jarvis.shield.domain.repository.ShieldRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class ShieldRepositoryImpl @Inject constructor(
    private val dao: ScanEventDao,
    private val preferences: ShieldPreferences,
) : ShieldRepository {
    override val monitoringEnabled: Flow<Boolean> = preferences.monitoringEnabled
    override val scanCount: Flow<Int> = dao.observeCount()
    override val latestScan: Flow<ScanSummary?> = dao.observeLatest().map { event ->
        event?.let {
            ScanSummary(
                completedAtEpochMs = it.completedAtEpochMs,
                findingsCount = it.findingsCount,
                criticalCount = it.criticalCount,
                status = it.status,
            )
        }
    }

    override suspend fun setMonitoringEnabled(enabled: Boolean) {
        preferences.setMonitoringEnabled(enabled)
    }

    override suspend fun recordFoundationVerification() {
        val now = System.currentTimeMillis()
        dao.insert(
            ScanEventEntity(
                startedAtEpochMs = now,
                completedAtEpochMs = now,
                findingsCount = 0,
                criticalCount = 0,
                status = "PHASE_1_FOUNDATION_VERIFIED",
            ),
        )
    }
}
