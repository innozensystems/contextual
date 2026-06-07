package com.contextual.service

import com.contextual.BuildConfig
import com.contextual.util.CertificatePinningConfig
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.android.Android
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object ProxyService {

    private val baseUrl = BuildConfig.PROXY_BASE_URL
    private val apiKey = BuildConfig.PROXY_API_KEY

    // Stable device identifier for per-device rate limiting.
    private val deviceId: String = UUID.randomUUID().toString()

    private val client: HttpClient by lazy { createClient() }

    init {
        if (!BuildConfig.DEBUG) {
            require(baseUrl.startsWith("https://")) {
                "PROXY_BASE_URL must use HTTPS in release builds: $baseUrl"
            }
            require(apiKey.isNotBlank()) {
                "PROXY_API_KEY must be set for release builds"
            }
        }
    }

    private fun createClient(): HttpClient {
        val jsonConfig = Json { ignoreUnknownKeys = true }
        val pins = CertificatePinningConfig.parsePins(BuildConfig.PROXY_CERTIFICATE_PINS)
        val defaultHeadersBlock: io.ktor.client.HttpClientConfig<*>.() -> Unit = {
            install(ContentNegotiation) {
                json(jsonConfig)
            }
            defaultRequest {
                header("x-device-id", deviceId)
                if (apiKey.isNotBlank()) {
                    header("x-api-key", apiKey)
                }
            }
        }
        return if (!BuildConfig.DEBUG && pins.isNotEmpty()) {
            // Release build with pinned certificates → OkHttp engine
            val hostname = baseUrl.removePrefix("https://").removePrefix("http://").split("/").first()
            val pinner = CertificatePinningConfig.createPinner(hostname, pins)
            HttpClient(OkHttp) {
                engine {
                    config {
                        if (pinner != null) {
                            certificatePinner(pinner)
                        }
                    }
                }
                defaultHeadersBlock()
            }
        } else {
            // Debug or no pins → default Android engine
            HttpClient(Android) {
                defaultHeadersBlock()
            }
        }
    }

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

    @Serializable
    private data class ErrorBody(val detail: String? = null)

    sealed class ProxyException(message: String) : Exception(message) {
        class RateLimited(detail: String?) : ProxyException(detail ?: "Too many requests. Please try again later.")
        class MapboxUnavailable(detail: String?) : ProxyException(detail ?: "Routing service is unavailable. Please try again later.")
        class NotConfigured(detail: String?) : ProxyException(detail ?: "Service is not configured. Contact support.")
        class NotFound(detail: String?) : ProxyException(detail ?: "No results found.")
        class BadRequest(detail: String?) : ProxyException(detail ?: "Invalid request.")
        class HttpError(val status: Int, detail: String?) : ProxyException(detail ?: "Server error $status.")
        class CertificatePinningFailed : ProxyException("Secure connection could not be established. Contact support.")
    }

    private suspend inline fun <reified T> safeRequest(block: () -> T): T {
        return try {
            block()
        } catch (e: io.ktor.client.plugins.ClientRequestException) {
            val detail = parseError(e.response)
            when (e.response.status.value) {
                429 -> throw ProxyException.RateLimited(detail)
                404 -> throw ProxyException.NotFound(detail)
                400, 422 -> throw ProxyException.BadRequest(detail)
                else -> throw ProxyException.HttpError(e.response.status.value, detail)
            }
        } catch (e: io.ktor.client.plugins.ServerResponseException) {
            val detail = parseError(e.response)
            when (e.response.status.value) {
                502 -> throw ProxyException.MapboxUnavailable(detail)
                503 -> throw ProxyException.NotConfigured(detail)
                else -> throw ProxyException.HttpError(e.response.status.value, detail)
            }
        } catch (e: io.ktor.client.network.sockets.SocketTimeoutException) {
            throw ProxyException.MapboxUnavailable("Connection timed out")
        } catch (e: io.ktor.client.network.sockets.ConnectTimeoutException) {
            throw ProxyException.MapboxUnavailable("Connection timed out")
        }
    }

    private suspend fun parseError(response: io.ktor.client.statement.HttpResponse): String? {
        return try {
            response.body<ErrorBody>().detail
        } catch (_: Exception) {
            null
        }
    }

    suspend fun geocode(query: String): List<GeocodeResult> = safeRequest {
        val response = client.post("$baseUrl/geocode") {
            contentType(ContentType.Application.Json)
            setBody(GeocodeRequest(query = query))
        }
        response.body<GeocodeResponse>().results
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

    suspend fun route(waypoints: List<Pair<Double, Double>>): RouteResponse = safeRequest {
        val response = client.post("$baseUrl/route") {
            contentType(ContentType.Application.Json)
            setBody(RouteRequest(waypoints = waypoints.map { listOf(it.first, it.second) }))
        }
        response.body()
    }
}
