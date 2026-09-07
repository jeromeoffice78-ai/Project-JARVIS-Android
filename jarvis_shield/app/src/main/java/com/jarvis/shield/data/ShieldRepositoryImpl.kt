package com.jarvis.shield.data

import com.jarvis.shield.data.local.ScanEventDao
import com.jarvis.shield.data.local.ScanEventEntity
import com.jarvis.shield.data.preferences.ShieldPreferences
import com.jarvis.shield.data.scanner.AndroidSecurityScanner
import com.jarvis.shield.domain.model.ScanSummary
import com.jarvis.shield.domain.model.SecurityScanResult
import com.jarvis.shield.domain.repository.ShieldRepository
import java.util.concurrent.CancellationException
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class ShieldRepositoryImpl @Inject constructor(
    private val dao: ScanEventDao,
    private val preferences: ShieldPreferences,
    private val scanner: AndroidSecurityScanner,
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

    override suspend fun runSecurityScan(): Result<SecurityScanResult> {
        val startedAt = System.currentTimeMillis()
        return try {
            val result = scanner.scan()
            dao.insert(
                ScanEventEntity(
                    startedAtEpochMs = result.startedAtEpochMs,
                    completedAtEpochMs = result.completedAtEpochMs,
                    findingsCount = result.findings.size,
                    criticalCount = result.criticalCount,
                    status = when {
                        result.criticalCount > 0 -> "CRITICAL_RISK_INDICATORS"
                        result.highCount > 0 -> "HIGH_RISK_INDICATORS"
                        result.findings.isNotEmpty() -> "REVIEW_RISK_INDICATORS"
                        else -> "NO_RISK_INDICATORS"
                    },
                ),
            )
            Result.success(result)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Throwable) {
            try {
                val finishedAt = System.currentTimeMillis()
                dao.insert(
                    ScanEventEntity(
                        startedAtEpochMs = startedAt,
                        completedAtEpochMs = finishedAt,
                        findingsCount = 0,
                        criticalCount = 0,
                        status = "SCAN_FAILED",
                    ),
                )
            } catch (_: Throwable) {
                // Preserve the original scanner failure even if local history storage also fails.
            }
            Result.failure(error)
        }
    }
}
