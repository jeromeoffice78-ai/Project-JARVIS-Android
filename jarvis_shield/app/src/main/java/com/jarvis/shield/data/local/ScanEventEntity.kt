package com.jarvis.shield.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "scan_events")
data class ScanEventEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val startedAtEpochMs: Long,
    val completedAtEpochMs: Long,
    val findingsCount: Int,
    val criticalCount: Int,
    val status: String,
)
