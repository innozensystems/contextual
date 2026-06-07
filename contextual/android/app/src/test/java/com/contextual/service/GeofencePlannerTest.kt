package com.contextual.service

import com.contextual.data.Location
import com.contextual.data.Task
import com.contextual.data.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Test

class GeofencePlannerTest {

    private fun makeTask(
        id: String,
        status: TaskStatus = TaskStatus.ACTIVE,
        lat: Double? = 37.0,
        lng: Double? = -122.0,
        radius: Int = 200
    ): Task {
        return Task(
            id = id,
            userId = "user-1",
            title = "Task $id",
            status = status,
            reminderRadiusMeters = radius,
            locations = if (lat != null && lng != null) {
                Location(name = "Loc $id", latitude = lat, longitude = lng)
            } else null
        )
    }

    @Test
    fun `buildSpecs filters only active tasks`() {
        val tasks = listOf(
            makeTask("1", status = TaskStatus.ACTIVE),
            makeTask("2", status = TaskStatus.COMPLETED),
            makeTask("3", status = TaskStatus.ARCHIVED)
        )
        val specs = GeofencePlanner.buildSpecs(tasks)
        assertEquals(1, specs.size)
        assertEquals("task-1", specs[0].requestId)
    }

    @Test
    fun `buildSpecs skips tasks without coordinates`() {
        val tasks = listOf(
            makeTask("1", lat = 37.0, lng = -122.0),
            makeTask("2", lat = null, lng = null),
            makeTask("3", lat = 37.1, lng = -122.1)
        )
        val specs = GeofencePlanner.buildSpecs(tasks)
        assertEquals(2, specs.size)
        assertEquals("task-1", specs[0].requestId)
        assertEquals("task-3", specs[1].requestId)
    }

    @Test
    fun `buildSpecs limits to 20 geofences`() {
        val tasks = (1..25).map { makeTask(it.toString()) }
        val specs = GeofencePlanner.buildSpecs(tasks)
        assertEquals(20, specs.size)
    }

    @Test
    fun `buildSpecs preserves radius`() {
        val tasks = listOf(makeTask("1", radius = 500))
        val specs = GeofencePlanner.buildSpecs(tasks)
        assertEquals(500, specs[0].radiusMeters)
    }

    @Test
    fun `buildSpecs returns empty list for no active tasks`() {
        val tasks = listOf(
            makeTask("1", status = TaskStatus.COMPLETED),
            makeTask("2", status = TaskStatus.ARCHIVED)
        )
        val specs = GeofencePlanner.buildSpecs(tasks)
        assertEquals(0, specs.size)
    }

    @Test
    fun `buildSpecs returns empty list when all tasks lack coordinates`() {
        val tasks = listOf(
            makeTask("1", lat = null, lng = null),
            makeTask("2", lat = null, lng = null)
        )
        val specs = GeofencePlanner.buildSpecs(tasks)
        assertEquals(0, specs.size)
    }
}
