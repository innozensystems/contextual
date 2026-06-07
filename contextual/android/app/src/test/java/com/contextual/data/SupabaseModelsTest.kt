package com.contextual.data

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SupabaseModelsTest {

    private val json = Json { ignoreUnknownKeys = true }

    // MARK: - Task with embedded location (Supabase joined query)

    @Test
    fun `task decodes from Supabase joined query with location`() {
        val payload = """
            {
                "id": "task-1",
                "user_id": "user-1",
                "title": "Buy milk",
                "location_id": "loc-1",
                "status": "active",
                "priority": "normal",
                "reminder_radius_meters": 200,
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z",
                "locations": {
                    "id": "loc-1",
                    "name": "Whole Foods",
                    "address": "123 Market St",
                    "latitude": 37.7749,
                    "longitude": -122.4194,
                    "place_id": "mbx-123"
                }
            }
        """.trimIndent()

        val task = json.decodeFromString<Task>(payload)
        assertEquals("Buy milk", task.title)
        assertEquals("loc-1", task.locationId)
        assertEquals("Whole Foods", task.locations?.name)
        assertEquals(37.7749, task.locations?.latitude ?: 0.0, 0.0001)
        assertEquals(-122.4194, task.locations?.longitude ?: 0.0, 0.0001)
    }

    @Test
    fun `task decodes from Supabase without location`() {
        val payload = """
            {
                "id": "task-1",
                "user_id": "user-1",
                "title": "Buy milk",
                "status": "active",
                "priority": "normal",
                "reminder_radius_meters": 200,
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z"
            }
        """.trimIndent()

        val task = json.decodeFromString<Task>(payload)
        assertEquals("Buy milk", task.title)
        assertNull(task.locationId)
        assertNull(task.locations)
    }

    @Test
    fun `task serializes status as string`() {
        val task = Task(
            id = "task-1",
            userId = "user-1",
            title = "Test",
            status = TaskStatus.COMPLETED
        )
        val encoded = json.encodeToString(task)
        assertEquals(true, encoded.contains("\"status\":\"completed\""))
    }

    @Test
    fun `task serializes priority as string`() {
        val task = Task(
            id = "task-1",
            userId = "user-1",
            title = "Test",
            priority = TaskPriority.URGENT
        )
        val encoded = json.encodeToString(task)
        assertEquals(true, encoded.contains("\"priority\":\"urgent\""))
    }

    // MARK: - Location model

    @Test
    fun `location decodes from Supabase`() {
        val payload = """
            {
                "id": "loc-1",
                "name": "Whole Foods",
                "address": "123 Market St",
                "latitude": 37.7749,
                "longitude": -122.4194,
                "place_id": "mbx-123",
                "created_by": "user-1",
                "created_at": "2024-01-01T00:00:00Z"
            }
        """.trimIndent()

        val loc = json.decodeFromString<Location>(payload)
        assertEquals("Whole Foods", loc.name)
        assertEquals(37.7749, loc.latitude, 0.0001)
        assertEquals("mbx-123", loc.placeId)
    }

    @Test
    fun `location serializes with snake_case keys`() {
        val loc = Location(
            id = "loc-1",
            name = "Test",
            latitude = 37.0,
            longitude = -122.0,
            placeId = "mbx-456"
        )
        val encoded = json.encodeToString(loc)
        assertEquals(true, encoded.contains("\"place_id\":\"mbx-456\""))
    }

    // MARK: - TaskList model

    @Test
    fun `taskList decodes from Supabase`() {
        val payload = """
            {
                "id": "list-1",
                "name": "Groceries",
                "owner_id": "user-1",
                "is_shared": true,
                "sync_policy": "realtime",
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z"
            }
        """.trimIndent()

        val list = json.decodeFromString<TaskList>(payload)
        assertEquals("Groceries", list.name)
        assertEquals(true, list.isShared)
        assertEquals("realtime", list.syncPolicy)
    }

    // MARK: - Enum serialization

    @Test
    fun `taskStatus serializes correctly`() {
        assertEquals("\"active\"", json.encodeToString(TaskStatus.ACTIVE))
        assertEquals("\"completed\"", json.encodeToString(TaskStatus.COMPLETED))
        assertEquals("\"archived\"", json.encodeToString(TaskStatus.ARCHIVED))
    }

    @Test
    fun `taskPriority serializes correctly`() {
        assertEquals("\"low\"", json.encodeToString(TaskPriority.LOW))
        assertEquals("\"normal\"", json.encodeToString(TaskPriority.NORMAL))
        assertEquals("\"high\"", json.encodeToString(TaskPriority.HIGH))
        assertEquals("\"urgent\"", json.encodeToString(TaskPriority.URGENT))
    }
}
