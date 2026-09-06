package com.jarvis.shield.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.jarvis.shield.domain.model.ScanSummary
import com.jarvis.shield.domain.repository.ShieldRepository
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
) : ViewModel() {
    private val errorMessage = MutableStateFlow<String?>(null)
    private val isWorking = MutableStateFlow(false)

    val uiState: StateFlow<ShieldUiState> = combine(
        repository.monitoringEnabled,
        repository.scanCount,
        repository.latestScan,
        errorMessage,
        isWorking,
    ) { monitoring, count, latest, error, working ->
        ShieldUiState(
            monitoringEnabled = monitoring,
            verificationCount = count,
            latestVerification = latest,
            isWorking = working,
            errorMessage = error,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ShieldUiState(),
    )

    fun setMonitoringEnabled(enabled: Boolean) {
        viewModelScope.launch {
            runCatching { repository.setMonitoringEnabled(enabled) }
                .onFailure { errorMessage.value = it.message ?: "Unable to save protection preference." }
        }
    }

    fun verifyFoundation() {
        if (isWorking.value) return
        viewModelScope.launch {
            isWorking.value = true
            errorMessage.value = null
            runCatching { repository.recordFoundationVerification() }
                .onFailure { errorMessage.value = it.message ?: "Local security storage verification failed." }
            isWorking.value = false
        }
    }

    fun dismissError() {
        errorMessage.value = null
    }
}

data class ShieldUiState(
    val monitoringEnabled: Boolean = true,
    val verificationCount: Int = 0,
    val latestVerification: ScanSummary? = null,
    val isWorking: Boolean = false,
    val errorMessage: String? = null,
)
