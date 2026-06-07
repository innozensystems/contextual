package com.contextual.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return

        val triggeringGeofences = event.triggeringGeofences ?: return
        for (geofence in triggeringGeofences) {
            val taskId = geofence.requestId.removePrefix("task-")
            // Fetch task details and show notification
            NotificationHelper.showContextNotification(
                context,
                taskId = taskId,
                locationName = "Nearby", // Fetch from DB in production
                taskTitles = listOf("Task title") // Fetch from DB in production
            )
        }
    }
}
