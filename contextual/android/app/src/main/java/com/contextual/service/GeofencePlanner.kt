package com.contextual.service

import com.contextual.data.Task
import com.contextual.data.TaskStatus

/**
 * Pure Kotlin logic for deciding which tasks should become geofences.
 * No Android dependencies — testable on the JVM.
 */
object GeofencePlanner {
    const val MAX_GEOFENCES = 20

    data class Spec(
        val requestId: String,
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Int,
        val transitionEnter: Boolean = true
    )

    /**
     * Build geofence specs from a list of tasks.
     * Filters: active status + has location coordinates.
     * Sorts: by distance to current location when provided (nearest first).
     * Limits: at most [MAX_GEOFENCES] results.
     */
    fun buildSpecs(
        tasks: List<Task>,
        currentLat: Double? = null,
        currentLng: Double? = null
    ): List<Spec> {
        val withCoords = tasks
            .filter { it.status == TaskStatus.ACTIVE && it.locationId != null }
            .mapNotNull { task ->
                val lat = task.locations?.latitude
                val lng = task.locations?.longitude
                if (lat == null || lng == null) return@mapNotNull null
                val distance = if (currentLat != null && currentLng != null) {
                    haversineMeters(currentLat, currentLng, lat, lng)
                } else 0.0
                SpecWithDist(
                    task = task,
                    latitude = lat,
                    longitude = lng,
                    distance = distance
                )
            }

        val sorted = if (currentLat != null && currentLng != null) {
            withCoords.sortedBy { it.distance }
        } else {
            withCoords
        }

        return sorted.take(MAX_GEOFENCES).map {
            Spec(
                requestId = "task-${it.task.id}",
                latitude = it.latitude,
                longitude = it.longitude,
                radiusMeters = it.task.reminderRadiusMeters
            )
        }
    }

    private data class SpecWithDist(
        val task: Task,
        val latitude: Double,
        val longitude: Double,
        val distance: Double
    )

    /** Haversine distance in meters. */
    private fun haversineMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val r = 6_371_000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = kotlin.math.sin(dLat / 2).pow(2) +
                kotlin.math.cos(Math.toRadians(lat1)) *
                kotlin.math.cos(Math.toRadians(lat2)) *
                kotlin.math.sin(dLng / 2).pow(2)
        return r * 2 * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))
    }
}
