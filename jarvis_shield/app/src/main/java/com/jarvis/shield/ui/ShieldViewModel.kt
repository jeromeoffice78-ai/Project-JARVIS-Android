package com.jarvis.shield.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.jarvis.shield.domain.model.ScanSummary
import com.jarvis.shield.domain.model.SecurityScanResult
import com.jarvis.shield.domain.repository.ShieldRepository
import com.jarvis.shield.domain.usecase.RunSecurityScanUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
class ShieldViewModel @Inject constructor(
    private val repository: ShieldRepository,
    private val runSecurityScan: RunSecurityScanUseCase,
) : ViewModel() {
    private val session = MutableStateFlow(ScanSession())

    val uiState: StateFlow<ShieldUiState> = combine(
        repository.monitoringEnabled,
        repository.scanCount,
        repository.latestScan,
        session,
    ) { monitoring, count, latest, scanSession ->
        ShieldUiState(
            monitoringEnabled = monitoring,
            scanCount = count,
            latestScan = latest,
            isScanning = scanSession.isScanning,
            currentResult = scanSession.result,
            errorMessage = scanSession.errorMessage,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ShieldUiState(),
    )

    fun setMonitoringEnabled(enabled: Boolean) {
        viewModelScope.launch {
            try {
                repository.setMonitoringEnabled(enabled)
            } catch (error: Throwable) {
                session.value = session.value.copy(
                    errorMessage = error.message?.takeIf { it.isNotBlank() }
                        ?: "Unable to save the protection preference.",
                )
            }
        }
    }

    fun scanNow() {
        if (session.value.isScanning) return
        viewModelScope.launch {
            session.value = session.value.copy(
                isScanning = true,
                errorMessage = null,
            )

            runSecurityScan().fold(
                onSuccess = { result ->
                    session.value = ScanSession(
                        isScanning = false,
                        result = result,
                        errorMessage = null,
                    )
                },
                onFailure = { error ->
                    session.value = session.value.copy(
                        isScanning = false,
                        errorMessage = error.message?.takeIf { it.isNotBlank() }
                            ?: "The device security scan could not be completed.",
                    )
                },
            )
        }
    }

    fun dismissError() {
        session.value = session.value.copy(errorMessage = null)
    }
}

private data class ScanSession(
    val isScanning: Boolean = false,
    val result: SecurityScanResult? = null,
    val errorMessage: String? = null,
)

data class ShieldUiState(
    val monitoringEnabled: Boolean = true,
    val scanCount: Int = 0,
    val latestScan: ScanSummary? = null,
    val isScanning: Boolean = false,
    val currentResult: SecurityScanResult? = null,
    val errorMessage: String? = null,
)
