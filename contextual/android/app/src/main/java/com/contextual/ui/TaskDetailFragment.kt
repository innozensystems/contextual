package com.contextual.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.navigation.fragment.findNavController
import com.contextual.data.SupabaseClient
import com.contextual.data.TaskStatus
import com.contextual.databinding.FragmentTaskDetailBinding
import kotlinx.coroutines.launch

class TaskDetailFragment : Fragment() {
    private var _binding: FragmentTaskDetailBinding? = null
    private val binding get() = _binding!!
    private lateinit var taskId: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        taskId = arguments?.getString("task_id") ?: ""
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentTaskDetailBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        binding.completeButton.setOnClickListener {
            lifecycleScope.launch {
                try {
                    SupabaseClient.completeTask(taskId)
                    binding.completeButton.isEnabled = false
                    binding.completeButton.text = "Completed"
                } catch (e: Exception) {
                    // Show error
                }
            }
        }

        binding.shareButton.setOnClickListener {
            PartnerInviteBottomSheet.newInstance(taskId)
                .show(parentFragmentManager, "partner_invite")
        }

        binding.deleteButton.setOnClickListener {
            lifecycleScope.launch {
                try {
                    SupabaseClient.deleteTask(taskId)
                    findNavController().popBackStack()
                } catch (e: Exception) {
                    // Show error
                }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

class PartnerInviteBottomSheet : com.google.android.material.bottomsheet.BottomSheetDialogFragment() {
    companion object {
        fun newInstance(taskId: String) = PartnerInviteBottomSheet().apply {
            arguments = Bundle().apply { putString("task_id", taskId) }
        }
    }
    // Invite UI implementation
}
