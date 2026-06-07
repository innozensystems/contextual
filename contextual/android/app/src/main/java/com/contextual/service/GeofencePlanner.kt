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
     * Limits: at most [MAX_GEOFENCES] results.
     */
    fun buildSpecs(tasks: List<Task>): List<Spec> {
        return tasks
            .filter { it.status == TaskStatus.ACTIVE && it.locationId != null }
            .mapNotNull { task ->
                val lat = task.locations?.latitude
                val lng = task.locations?.longitude
                if (lat == null || lng == null) return@mapNotNull null
                Spec(
                    requestId = "task-${task.id}",
                    latitude = lat,
                    longitude = lng,
                    radiusMeters = task.reminderRadiusMeters
                )
            }
            .take(MAX_GEOFENCES)
    }
}
