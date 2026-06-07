package com.contextual.service

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.contextual.data.Task
import kotlinx.coroutines.tasks.await

object GeofenceManager {
    @SuppressLint("MissingPermission")
    suspend fun updateGeofences(
        context: Context,
        tasks: List<Task>,
        currentLat: Double? = null,
        currentLng: Double? = null
    ) {
        val geofencingClient = LocationServices.getGeofencingClient(context)
        val specs = GeofencePlanner.buildSpecs(tasks, currentLat, currentLng)

        // Remove all existing
        geofencingClient.removeGeofences(getPendingIntent(context))

        // Add new
        val geofences = specs.map { spec ->
            Geofence.Builder()
                .setRequestId(spec.requestId)
                .setCircularRegion(spec.latitude, spec.longitude, spec.radiusMeters.toFloat())
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
