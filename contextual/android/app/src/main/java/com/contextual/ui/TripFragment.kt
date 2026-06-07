package com.contextual.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.contextual.databinding.FragmentTripBinding
import com.contextual.service.ProxyService
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.SupportMapFragment
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.MarkerOptions
import com.google.android.gms.maps.model.PolylineOptions
import com.contextual.R
import kotlinx.coroutines.launch

class TripFragment : Fragment() {
    private var _binding: FragmentTripBinding? = null
    private val binding get() = _binding!!
    private var googleMap: GoogleMap? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentTripBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val mapFragment = childFragmentManager.findFragmentById(R.id.map) as SupportMapFragment?
            ?: SupportMapFragment.newInstance().also {
                childFragmentManager.beginTransaction().replace(R.id.map, it).commit()
            }

        mapFragment.getMapAsync { map ->
            googleMap = map
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(37.7749, -122.4194), 12f))
        }

        binding.optimizeButton.setOnClickListener {
            optimizeRoute()
        }
    }

    private fun optimizeRoute() {
        lifecycleScope.launch {
            try {
                binding.optimizeButton.isEnabled = false
                binding.optimizeButton.text = "Optimizing..."
                binding.errorText.visibility = View.GONE

                // In production: use actual task coordinates
                val waypoints = listOf(
                    37.7749 to -122.4194,
                    37.7849 to -122.4094,
                    37.7649 to -122.4294
                )
                val route = ProxyService.route(waypoints)

                binding.durationText.text = formatDuration(route.durationSeconds)
                binding.distanceText.text = formatDistance(route.distanceMeters)

                googleMap?.let { map ->
                    map.clear()
                    waypoints.forEachIndexed { index, (lat, lng) ->
                        map.addMarker(
                            MarkerOptions()
                                .position(LatLng(lat, lng))
                                .title("Stop ${index + 1}")
                        )
                    }
                }
            } catch (e: ProxyService.ProxyException) {
                binding.errorText.text = e.message
                binding.errorText.visibility = View.VISIBLE
                binding.optimizeButton.text = "Try again"
            } catch (e: Exception) {
                binding.errorText.text = "Something went wrong. Please try again."
                binding.errorText.visibility = View.VISIBLE
                binding.optimizeButton.text = "Try again"
            } finally {
                binding.optimizeButton.isEnabled = true
                if (binding.optimizeButton.text == "Optimizing...") {
                    binding.optimizeButton.text = "Optimize route"
                }
            }
        }
    }

    private fun formatDuration(seconds: Double): String {
        val mins = (seconds / 60).toInt()
        return if (mins < 60) "$mins min" else "${mins / 60}h ${mins % 60}m"
    }

    private fun formatDistance(meters: Double): String {
        return if (meters < 1000) "${meters.toInt()} m" else "%.1f km".format(meters / 1000)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
