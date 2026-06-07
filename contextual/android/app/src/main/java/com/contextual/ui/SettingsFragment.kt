package com.contextual.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.contextual.data.SupabaseClient
import com.contextual.databinding.FragmentSettingsBinding
import kotlinx.coroutines.launch

class SettingsFragment : Fragment() {
    private var _binding: FragmentSettingsBinding? = null
    private val binding get() = _binding!!

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        binding.locationToggle.isChecked = ContextCompat.checkSelfPermission(
            requireContext(), Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        binding.locationToggle.setOnCheckedChangeListener { _, checked ->
            if (checked) {
                ActivityCompat.requestPermissions(
                    requireActivity(),
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                    100
                )
            }
        }

        binding.reduceMotionToggle.setOnCheckedChangeListener { _, checked ->
            getSharedPreferences().edit().putBoolean("reduce_motion", checked).apply()
        }

        binding.signOutButton.setOnClickListener {
            lifecycleScope.launch {
                try {
                    // SupabaseClient.signOut() in production
                    activity?.finish()
                } catch (e: Exception) {
                    // Handle error
                }
            }
        }
    }

    private fun getSharedPreferences() =
        requireActivity().getSharedPreferences("app_prefs", android.content.Context.MODE_PRIVATE)

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
