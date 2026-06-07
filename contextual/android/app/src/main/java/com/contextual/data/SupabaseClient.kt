package com.contextual.data

import android.content.Context
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.gotrue.auth
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.contextual.BuildConfig

object SupabaseClient {
    private var client: SupabaseClient? = null

    fun init(context: Context) {
        client = createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY
        ) {
            // Default configuration
        }
    }

    fun get(): SupabaseClient = client ?: throw IllegalStateException("SupabaseClient not initialized")

    suspend fun fetchTasks(userId: String): List<Task> = withContext(Dispatchers.IO) {
        get().from("tasks")
            .select(Columns.raw("*, locations:location_id(*)")) {
                filter { eq("user_id", userId) }
                filter { neq("status", "archived") }
                order("created_at", Order.DESCENDING)
            }
            .decodeList<Task>()
    }

    suspend fun createTask(task: Task): Task = withContext(Dispatchers.IO) {
        get().from("tasks")
            .insert(task) { select() }
            .decodeSingle<Task>()
    }

    suspend fun updateTask(task: Task) = withContext(Dispatchers.IO) {
        get().from("tasks")
            .update(task) {
                filter { eq("id", task.id) }
            }
    }

    suspend fun deleteTask(taskId: String) = withContext(Dispatchers.IO) {
        get().from("tasks")
            .delete {
                filter { eq("id", taskId) }
            }
    }

    suspend fun completeTask(taskId: String) = withContext(Dispatchers.IO) {
        get().from("tasks")
            .update({
                mapOf(
                    "status" to "completed",
                    "completed_at" to java.time.Instant.now().toString()
                )
            }) {
                filter { eq("id", taskId) }
            }
    }

    suspend fun createLocation(location: Location): Location = withContext(Dispatchers.IO) {
        get().from("locations")
            .insert(location) { select() }
            .decodeSingle<Location>()
    }

    suspend fun fetchLists(userId: String): List<TaskList> = withContext(Dispatchers.IO) {
        get().from("lists")
            .select {
                filter { eq("owner_id", userId) }
            }
            .decodeList<TaskList>()
    }
}
