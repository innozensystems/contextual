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
import android.util.Log

object SupabaseClient {
    private var client: SupabaseClient? = null

    fun init(context: Context) {
        val url = BuildConfig.SUPABASE_URL
        val key = BuildConfig.SUPABASE_ANON_KEY
        require(url.isNotBlank() && url.startsWith("http")) {
            "SUPABASE_URL is not configured. Set SUPABASE_URL in environment before building."
        }
        require(key.isNotBlank()) {
            "SUPABASE_ANON_KEY is not configured. Set SUPABASE_ANON_KEY in environment before building."
        }
        client = createSupabaseClient(
            supabaseUrl = url,
            supabaseKey = key
        ) {
            install(io.github.jan.supabase.gotrue.Auth) {
                // Default auth configuration
            }
        }
    }

    suspend fun signInAnonymous(): String? {
        return try {
            client?.auth?.signInAnonymously()
            val user = client?.auth?.currentUserOrNull()
            Log.d("SupabaseClient", "Signed in anonymously as ${user?.id}")
            user?.id
        } catch (e: Exception) {
            Log.e("SupabaseClient", "Anonymous sign-in failed", e)
            null
        }
    }

    fun currentUserId(): String? = client?.auth?.currentUserOrNull()?.id

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
