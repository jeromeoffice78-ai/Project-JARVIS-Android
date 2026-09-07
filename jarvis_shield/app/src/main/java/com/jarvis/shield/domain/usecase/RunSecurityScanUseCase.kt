package com.jarvis.shield.domain.usecase

import com.jarvis.shield.domain.model.SecurityScanResult
import com.jarvis.shield.domain.repository.ShieldRepository
import javax.inject.Inject

class RunSecurityScanUseCase @Inject constructor(
    private val repository: ShieldRepository,
) {
    suspend operator fun invoke(): Result<SecurityScanResult> = repository.runSecurityScan()
}
