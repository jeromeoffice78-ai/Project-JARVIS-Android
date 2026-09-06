package com.jarvis.shield.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [ScanEventEntity::class],
    version = 1,
    exportSchema = true,
)
abstract class ShieldDatabase : RoomDatabase() {
    abstract fun scanEventDao(): ScanEventDao
}
