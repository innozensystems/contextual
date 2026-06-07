package com.contextual.service

import com.contextual.BuildConfig
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.android.Android
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object ProxyService {
    private val client = HttpClient(Android) {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }

    private val baseUrl = BuildConfig.PROXY_BASE_URL

    @Serializable
    data class GeocodeRequest(
        val query: String,
        @SerialName("proximity_lat") val proximityLat: Double? = null,
        @SerialName("proximity_lng") val proximityLng: Double? = null,
        val limit: Int = 5
    )

    @Serializable
    data class GeocodeResult(
        val name: String,
        val address: String? = null,
        val latitude: Double,
        val longitude: Double,
        @SerialName("place_id") val placeId: String? = null
    )

    @Serializable
    data class GeocodeResponse(
        val results: List<GeocodeResult>,
        val source: String,
        val cached: Boolean
    )

    suspend fun geocode(query: String): List<GeocodeResult> {
        val response = client.post("$baseUrl/geocode") {
            contentType(ContentType.Application.Json)
            setBody(GeocodeRequest(query = query))
        }
        return response.body<GeocodeResponse>().results
    }

    @Serializable
    data class RouteRequest(
        val waypoints: List<List<Double>>,
        val optimize: Boolean = true,
        val profile: String = "mapbox/driving"
    )

    @Serializable
    data class RouteResponse(
        @SerialName("distance_meters") val distanceMeters: Double,
        @SerialName("duration_seconds") val durationSeconds: Double,
        @SerialName("waypoints_order") val waypointsOrder: List<Int>,
        val geometry: String? = null
    )

    suspend fun route(waypoints: List<Pair<Double, Double>>): RouteResponse {
        val response = client.post("$baseUrl/route") {
            contentType(ContentType.Application.Json)
            setBody(RouteRequest(waypoints = waypoints.map { listOf(it.first, it.second) }))
        }
        return response.body()
    }
}
