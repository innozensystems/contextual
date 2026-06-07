package com.contextual.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.LinearLayoutManager
import com.contextual.data.SupabaseClient
import com.contextual.data.Task
import com.contextual.data.TaskStatus
import com.contextual.databinding.FragmentHomeBinding
import com.contextual.service.GeofenceManager
import com.contextual.service.NotificationHelper
import kotlinx.coroutines.launch

class HomeFragment : Fragment() {
    private var _binding: FragmentHomeBinding? = null
    private val binding get() = _binding!!
    private val viewModel: HomeViewModel by viewModels()
    private lateinit var taskAdapter: TaskAdapter

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentHomeBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        setupRecyclerView()
        setupSwipeRefresh()
        setupFab()
        setupTripBanner()
        observeViewModel()

        viewModel.loadTasks()
    }

    private fun setupRecyclerView() {
        taskAdapter = TaskAdapter(
            onComplete = { task -> viewModel.completeTask(task) },
            onClick = { task ->
                findNavController().navigate(
                    HomeFragmentDirections.actionHomeToTaskDetail(task.id)
                )
            }
        )
        binding.recyclerView.apply {
            layoutManager = LinearLayoutManager(context)
            adapter = taskAdapter
        }
    }

    private fun setupSwipeRefresh() {
        binding.swipeRefresh.setOnRefreshListener {
            viewModel.loadTasks()
        }
    }

    private fun setupFab() {
        binding.fabAdd.setOnClickListener {
            AddTaskBottomSheet.newInstance()
                .show(parentFragmentManager, "add_task")
        }
    }

    private fun setupTripBanner() {
        binding.tripBanner.setOnClickListener {
            findNavController().navigate(
                HomeFragmentDirections.actionHomeToTrip()
            )
        }
    }

    private fun observeViewModel() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel.tasks.collect { tasks ->
                        taskAdapter.submitList(tasks)
                        binding.emptyState.visibility = if (tasks.isEmpty()) View.VISIBLE else View.GONE

                        // Update geofences
                        context?.let { ctx ->
                            GeofenceManager.updateGeofences(ctx, tasks)
                        }
                    }
                }
                launch {
                    viewModel.isLoading.collect { loading ->
                        binding.swipeRefresh.isRefreshing = loading
                    }
                }
                launch {
                    viewModel.showTripBanner.collect { show ->
                        binding.tripBanner.visibility = if (show) View.VISIBLE else View.GONE
                    }
                }
                launch {
                    viewModel.errorMessage.collect { error ->
                        binding.errorBanner.apply {
                            visibility = if (error != null) View.VISIBLE else View.GONE
                            text = error
                        }
                    }
                }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
