package com.contextual.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class TaskStatus {
    @SerialName("active") ACTIVE,
    @SerialName("completed") COMPLETED,
    @SerialName("archived") ARCHIVED
}

@Serializable
enum class TaskPriority {
    @SerialName("low") LOW,
    @SerialName("normal") NORMAL,
    @SerialName("high") HIGH,
    @SerialName("urgent") URGENT
}

@Serializable
data class Task(
    val id: String = UUID.randomUUID().toString(),
    @SerialName("user_id") val userId: String,
    val title: String,
    val notes: String? = null,
    @SerialName("location_id") val locationId: String? = null,
    val status: TaskStatus = TaskStatus.ACTIVE,
    val priority: TaskPriority = TaskPriority.NORMAL,
    @SerialName("due_date") val dueDate: String? = null,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("reminder_radius_meters") val reminderRadiusMeters: Int = 200,
    @SerialName("is_hard_to_get") val isHardToGet: Boolean = false,
    @SerialName("list_id") val listId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)

@Serializable
data class Location(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val address: String? = null,
    val latitude: Double,
    val longitude: Double,
    @SerialName("place_id") val placeId: String? = null,
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String? = null
)

@Serializable
data class TaskList(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    @SerialName("owner_id") val ownerId: String,
    @SerialName("is_shared") val isShared: Boolean = false,
    @SerialName("sync_policy") val syncPolicy: String = "realtime",
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null
)
