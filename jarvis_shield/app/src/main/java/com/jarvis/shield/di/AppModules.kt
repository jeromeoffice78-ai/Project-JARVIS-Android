package com.jarvis.shield.di

import android.content.Context
import androidx.room.Room
import com.jarvis.shield.data.ShieldRepositoryImpl
import com.jarvis.shield.data.local.ScanEventDao
import com.jarvis.shield.data.local.ShieldDatabase
import com.jarvis.shield.domain.repository.ShieldRepository
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {
    @Binds
    @Singleton
    abstract fun bindShieldRepository(
        implementation: ShieldRepositoryImpl,
    ): ShieldRepository
}

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {
    @Provides
    @Singleton
    fun provideDatabase(
        @ApplicationContext context: Context,
    ): ShieldDatabase = Room.databaseBuilder(
        context,
        ShieldDatabase::class.java,
        "jarvis_shield.db",
    ).fallbackToDestructiveMigrationOnDowngrade().build()

    @Provides
    fun provideScanEventDao(database: ShieldDatabase): ScanEventDao = database.scanEventDao()
}
