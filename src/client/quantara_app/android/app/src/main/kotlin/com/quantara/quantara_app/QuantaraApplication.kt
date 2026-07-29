package com.quantara.quantara_app

import android.app.Application
import android.util.Log
import androidx.work.Configuration

/**
 * Provides WorkManager configuration without initializing it during process startup.
 *
 * Android's default WorkManager App Startup initializer is removed in the merged
 * manifest. The first post-frame background request initializes WorkManager on
 * demand through this provider, keeping optional background work out of the
 * launch-critical path.
 */
class QuantaraApplication : Application(), Configuration.Provider {
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(Log.ERROR)
            .build()
}
