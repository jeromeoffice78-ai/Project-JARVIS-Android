package com.jarvis.shield.domain.model

data class ScanSummary(
    val completedAtEpochMs: Long,
    val findingsCount: Int,
    val criticalCount: Int,
    val status: String,
)
