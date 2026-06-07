package com.contextual.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.SpeechRecognizer
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.widget.doAfterTextChanged
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.contextual.BuildConfig
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
        const val REQUEST_RECORD_AUDIO = 101
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
        val priorities = TaskPriority.values().map { it.name.replaceFirstChar { ch -> ch.uppercase() } }
        binding.prioritySpinner.adapter = ArrayAdapter(
            requireContext(),
            android.R.layout.simple_spinner_dropdown_item,
            priorities
        )
    }

    private fun setupLocationSearch() {
        // Clear error when user edits the location field
        binding.locationInput.doAfterTextChanged {
            binding.locationInputLayout.error = null
        }

        binding.searchLocationButton.setOnClickListener {
            val query = binding.locationInput.text.toString().trim()
            if (query.isEmpty()) {
                binding.locationInputLayout.error = "Enter a location name"
                return@setOnClickListener
            }

            // Early warning if proxy is not configured
            val baseUrl = BuildConfig.PROXY_BASE_URL
            if (baseUrl.isBlank() || baseUrl == "http://localhost:8000") {
                Toast.makeText(
                    requireContext(),
                    "Proxy not configured. Set PROXY_BASE_URL in local.properties or environment.",
                    Toast.LENGTH_LONG
                ).show()
            }

            searchLocation(query)
        }
    }

    private fun searchLocation(query: String) {
        lifecycleScope.launch {
            try {
                binding.searchLocationButton.isEnabled = false
                binding.locationInputLayout.error = null

                val results = ProxyService.geocode(query)
                if (results.isNotEmpty()) {
                    selectedLocation = results.first()
                    binding.locationInput.setText(results.first().name)
                    Toast.makeText(
                        requireContext(),
                        "Selected: ${results.first().name}",
                        Toast.LENGTH_SHORT
                    ).show()
                } else {
                    binding.locationInputLayout.error = "No locations found"
                }
            } catch (e: ProxyService.ProxyException) {
                val msg = e.message ?: "Location search failed"
                binding.locationInputLayout.error = msg
                Toast.makeText(requireContext(), msg, Toast.LENGTH_LONG).show()
            } catch (e: Exception) {
                val msg = e.message ?: "Location search failed"
                binding.locationInputLayout.error = "Location not found"
                Toast.makeText(requireContext(), "Error: $msg", Toast.LENGTH_LONG).show()
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
                binding.errorText.visibility = View.GONE

                val userId = SupabaseClient.currentUserId()
                    ?: throw IllegalStateException("Not signed in — enable anonymous auth in Supabase")
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
            } catch (e: IllegalStateException) {
                val msg = e.message ?: "Configuration error"
                binding.errorText.text = msg
                binding.errorText.visibility = View.VISIBLE
                Toast.makeText(requireContext(), msg, Toast.LENGTH_LONG).show()
                android.util.Log.e("AddTask", "Save failed (config)", e)
            } catch (e: Exception) {
                val msg = e.message ?: "Unknown error"
                binding.errorText.text = "Failed to save: $msg"
                binding.errorText.visibility = View.VISIBLE
                Toast.makeText(requireContext(), "Save failed: $msg", Toast.LENGTH_LONG).show()
                android.util.Log.e("AddTask", "Save failed", e)
            } finally {
                binding.saveButton.isEnabled = true
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
