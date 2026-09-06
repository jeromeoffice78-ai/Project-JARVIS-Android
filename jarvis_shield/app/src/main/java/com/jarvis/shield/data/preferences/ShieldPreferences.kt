package com.jarvis.shield.data.preferences

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.shieldDataStore by preferencesDataStore(name = "shield_preferences")

@Singleton
class ShieldPreferences @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private object Keys {
        val monitoringEnabled = booleanPreferencesKey("monitoring_enabled")
    }

    val monitoringEnabled: Flow<Boolean> = context.shieldDataStore.data
        .map { preferences -> preferences[Keys.monitoringEnabled] ?: true }

    suspend fun setMonitoringEnabled(enabled: Boolean) {
        context.shieldDataStore.edit { preferences ->
            preferences[Keys.monitoringEnabled] = enabled
        }
    }
}
