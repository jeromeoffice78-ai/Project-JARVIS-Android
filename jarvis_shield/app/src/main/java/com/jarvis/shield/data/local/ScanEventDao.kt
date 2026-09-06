package com.jarvis.shield.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ScanEventDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(event: ScanEventEntity): Long

    @Query("SELECT COUNT(*) FROM scan_events")
    fun observeCount(): Flow<Int>

    @Query("SELECT * FROM scan_events ORDER BY completedAtEpochMs DESC LIMIT 1")
    fun observeLatest(): Flow<ScanEventEntity?>
}
