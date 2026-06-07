package com.contextual.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.contextual.data.SupabaseClient
import com.contextual.data.Task
import com.contextual.data.TaskStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class HomeViewModel : ViewModel() {
    internal val _tasks = MutableStateFlow<List<Task>>(emptyList())
    val tasks: StateFlow<List<Task>> = _tasks.asStateFlow()

    internal val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    internal val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    internal val _showTripBanner = MutableStateFlow(false)
    val showTripBanner: StateFlow<Boolean> = _showTripBanner.asStateFlow()

    fun loadTasks() {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            try {
                val userId = SupabaseClient.currentUserId()
                    ?: SupabaseClient.signInAnonymous()
                    ?: throw IllegalStateException("Not signed in — enable anonymous auth in Supabase")
                val fetched = SupabaseClient.fetchTasks(userId)
                _tasks.value = fetched
                checkTripOpportunities()
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Can't load tasks — pull to retry"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun completeTask(task: Task) {
        viewModelScope.launch {
            try {
                SupabaseClient.completeTask(task.id)
                val updated = _tasks.value.map {
                    if (it.id == task.id) it.copy(status = TaskStatus.COMPLETED, completedAt = java.time.Instant.now().toString()) else it
                }
                _tasks.value = updated
                checkTripOpportunities()
            } catch (e: Exception) {
                _errorMessage.value = "Failed to complete task"
            }
        }
    }

    private fun checkTripOpportunities() {
        val active = _tasks.value.filter { it.status == TaskStatus.ACTIVE }
        _showTripBanner.value = active.size >= 3
    }
}
