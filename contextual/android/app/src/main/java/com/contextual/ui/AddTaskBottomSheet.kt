package com.contextual.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.SpeechRecognizer
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.contextual.data.Location
import com.contextual.data.SupabaseClient
import com.contextual.data.Task
import com.contextual.data.TaskPriority
import com.contextual.data.TaskStatus
import com.contextual.databinding.BottomSheetAddTaskBinding
import com.contextual.service.ProxyService
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.launch
import java.util.UUID

class AddTaskBottomSheet : BottomSheetDialogFragment() {
    private var _binding: BottomSheetAddTaskBinding? = null
    private val binding get() = _binding!!
    private var selectedLocation: ProxyService.GeocodeResult? = null

    companion object {
        fun newInstance() = AddTaskBottomSheet()
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = BottomSheetAddTaskBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        setupPrioritySpinner()
        setupLocationSearch()
        setupVoiceButton()
        setupSaveButton()
    }

    private fun setupPrioritySpinner() {
        val priorities = TaskPriority.values().map { it.name.capitalize() }
        binding.prioritySpinner.adapter = ArrayAdapter(
            requireContext(),
            android.R.layout.simple_spinner_dropdown_item,
            priorities
        )
    }

    private fun setupLocationSearch() {
        binding.searchLocationButton.setOnClickListener {
            val query = binding.locationInput.text.toString()
            if (query.isNotEmpty()) {
                searchLocation(query)
            }
        }
    }

    private fun searchLocation(query: String) {
        lifecycleScope.launch {
            try {
                binding.searchLocationButton.isEnabled = false
                val results = ProxyService.geocode(query)
                if (results.isNotEmpty()) {
                    selectedLocation = results.first()
                    binding.locationInput.setText(results.first().name)
                }
            } catch (e: Exception) {
                binding.locationInput.error = "Location not found"
            } finally {
                binding.searchLocationButton.isEnabled = true
            }
        }
    }

    private fun setupVoiceButton() {
        binding.voiceButton.setOnClickListener {
            if (ContextCompat.checkSelfPermission(requireContext(), Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED
            ) {
                startVoiceRecognition()
            } else {
                ActivityCompat.requestPermissions(
                    requireActivity(),
                    arrayOf(Manifest.permission.RECORD_AUDIO),
                    REQUEST_RECORD_AUDIO
                )
            }
        }
    }

    private fun startVoiceRecognition() {
        // In production: implement SpeechRecognizer intent
        binding.voiceButton.setImageResource(android.R.drawable.ic_btn_speak_now)
    }

    private fun setupSaveButton() {
        binding.saveButton.setOnClickListener {
            saveTask()
        }
    }

    private fun saveTask() {
        val title = binding.taskInput.text.toString().trim()
        if (title.isEmpty()) {
            binding.taskInput.error = "Task name required"
            return
        }

        lifecycleScope.launch {
            try {
                binding.saveButton.isEnabled = false

                val userId = "current-user-id" // Get from auth
                var locationId: String? = null

                selectedLocation?.let { loc ->
                    val location = Location(
                        name = loc.name,
                        address = loc.address,
                        latitude = loc.latitude,
                        longitude = loc.longitude,
                        placeId = loc.placeId,
                        createdBy = userId
                    )
                    val saved = SupabaseClient.createLocation(location)
                    locationId = saved.id
                }

                val task = Task(
                    userId = userId,
                    title = title,
                    notes = binding.notesInput.text.toString().takeIf { it.isNotEmpty() },
                    locationId = locationId,
                    priority = TaskPriority.values()[binding.prioritySpinner.selectedItemPosition]
                )

                SupabaseClient.createTask(task)
                dismiss()
            } catch (e: Exception) {
                binding.errorText.text = "Failed to save — will retry when online"
                binding.errorText.visibility = View.VISIBLE
            } finally {
                binding.saveButton.isEnabled = true
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    companion object {
        const val REQUEST_RECORD_AUDIO = 101
    }
}
