package com.contextual.service

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.contextual.data.Task
import kotlinx.coroutines.tasks.await

object GeofenceManager {
    private const val MAX_GEOFENCES = 20

    suspend fun updateGeofences(context: Context, tasks: List<Task>) {
        val geofencingClient = LocationServices.getGeofencingClient(context)
        val activeTasks = tasks.filter { it.status == TaskStatus.ACTIVE && it.locationId != null }
            .take(MAX_GEOFENCES)

        // Remove all existing
        geofencingClient.removeGeofences(getPendingIntent(context))

        // Add new
        val geofences = activeTasks.map { task ->
            Geofence.Builder()
                .setRequestId("task-${task.id}")
                .setCircularRegion(37.7749, -122.4194, task.reminderRadiusMeters.toFloat())
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .build()
        }

        if (geofences.isEmpty()) return

        val request = GeofencingRequest.Builder()
            .addGeofences(geofences)
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .build()

        geofencingClient.addGeofences(request, getPendingIntent(context)).await()
    }

    private fun getPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }
}
