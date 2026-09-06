package com.jarvis.shield

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.jarvis.shield.ui.ShieldScreen
import com.jarvis.shield.ui.ShieldViewModel
import com.jarvis.shield.ui.theme.JarvisShieldTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            JarvisShieldTheme {
                val viewModel: ShieldViewModel = hiltViewModel()
                val state by viewModel.uiState.collectAsStateWithLifecycle()
                ShieldScreen(
                    state = state,
                    onMonitoringChanged = viewModel::setMonitoringEnabled,
                    onVerifyFoundation = viewModel::verifyFoundation,
                )
            }
        }
    }
}
