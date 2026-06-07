package com.contextual.app

import android.app.Application
import com.contextual.data.SupabaseClient
import com.contextual.service.NotificationHelper

class ContextualApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SupabaseClient.init(this)
        NotificationHelper.createNotificationChannels(this)
    }
}
