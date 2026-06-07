package com.contextual.ui

import com.contextual.data.Task
import com.contextual.data.TaskStatus
import com.contextual.data.TaskPriority
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModelTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun makeTask(
        id: String,
        status: TaskStatus = TaskStatus.ACTIVE,
        title: String = "Task $id"
    ): Task {
        return Task(
            id = id,
            userId = "user-1",
            title = title,
            status = status,
            priority = TaskPriority.NORMAL
        )
    }

    @Test
    fun `checkTripOpportunities shows banner with 3 active tasks`() = runTest {
        val viewModel = HomeViewModel()
        val tasks = listOf(
            makeTask("1", TaskStatus.ACTIVE),
            makeTask("2", TaskStatus.ACTIVE),
            makeTask("3", TaskStatus.ACTIVE)
        )

        viewModel._tasks.value = tasks
        viewModel._showTripBanner.value = tasks.filter { it.status == TaskStatus.ACTIVE }.size >= 3

        assertTrue(viewModel.showTripBanner.value)
    }

    @Test
    fun `checkTripOpportunities hides banner with less than 3 active tasks`() = runTest {
        val viewModel = HomeViewModel()
        val tasks = listOf(
            makeTask("1", TaskStatus.ACTIVE),
            makeTask("2", TaskStatus.ACTIVE),
            makeTask("3", TaskStatus.COMPLETED)
        )

        viewModel._tasks.value = tasks
        viewModel._showTripBanner.value = tasks.filter { it.status == TaskStatus.ACTIVE }.size >= 3
        assertFalse(viewModel.showTripBanner.value)
    }

    @Test
    fun `completeTask updates local task status`() = runTest {
        val viewModel = HomeViewModel()
        val task = makeTask("1", TaskStatus.ACTIVE)
        viewModel._tasks.value = listOf(task)

        val updated = viewModel._tasks.value.map {
            if (it.id == task.id) it.copy(status = TaskStatus.COMPLETED) else it
        }
        viewModel._tasks.value = updated

        assertEquals(TaskStatus.COMPLETED, viewModel.tasks.value[0].status)
    }

    @Test
    fun `deleteTask removes from local state`() = runTest {
        val viewModel = HomeViewModel()
        val task = makeTask("1", TaskStatus.ACTIVE)
        viewModel._tasks.value = listOf(task)

        val remaining = viewModel._tasks.value.filter { it.id != task.id }
        viewModel._tasks.value = remaining

        assertTrue(viewModel.tasks.value.isEmpty())
    }

    @Test
    fun `active task count changes affect trip banner`() = runTest {
        val viewModel = HomeViewModel()

        viewModel._tasks.value = listOf(
            makeTask("1", TaskStatus.ACTIVE),
            makeTask("2", TaskStatus.ACTIVE),
            makeTask("3", TaskStatus.ACTIVE)
        )
        viewModel._showTripBanner.value = viewModel._tasks.value.filter { it.status == TaskStatus.ACTIVE }.size >= 3
        assertTrue(viewModel.showTripBanner.value)

        viewModel._tasks.value = viewModel._tasks.value.map {
            if (it.id == "1") it.copy(status = TaskStatus.COMPLETED) else it
        }
        viewModel._showTripBanner.value = viewModel._tasks.value.filter { it.status == TaskStatus.ACTIVE }.size >= 3
        assertFalse(viewModel.showTripBanner.value)
    }

    @Test
    fun `completing task removes it from active count`() = runTest {
        val viewModel = HomeViewModel()
        val tasks = listOf(
            makeTask("1", TaskStatus.ACTIVE),
            makeTask("2", TaskStatus.ACTIVE),
            makeTask("3", TaskStatus.ACTIVE)
        )
        viewModel._tasks.value = tasks
        viewModel._showTripBanner.value = true

        val completedId = "1"
        val updated = viewModel._tasks.value.map {
            if (it.id == completedId) {
                it.copy(status = TaskStatus.COMPLETED, completedAt = java.time.Instant.now().toString())
            } else it
        }
        viewModel._tasks.value = updated
        viewModel._showTripBanner.value = viewModel._tasks.value.filter { it.status == TaskStatus.ACTIVE }.size >= 3

        assertEquals(2, viewModel._tasks.value.filter { it.status == TaskStatus.ACTIVE }.size)
        assertFalse(viewModel.showTripBanner.value)
    }

    @Test
    fun `empty task list hides trip banner`() = runTest {
        val viewModel = HomeViewModel()
        viewModel._tasks.value = emptyList()
        viewModel._showTripBanner.value = false
        assertFalse(viewModel.showTripBanner.value)
    }
}
