package com.contextual.service

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProxyServiceTest {

    private fun mockClient(responseBody: String, status: HttpStatusCode = HttpStatusCode.OK): HttpClient {
        val engine = MockEngine {
            respond(
                content = responseBody,
                status = status,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }
        return HttpClient(engine) {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
        }
    }

    @Test
    fun `geocode parses response correctly`() = runBlocking {
        val json = """
            {
                "results": [
                    {
                        "name": "Whole Foods",
                        "address": "123 Market St",
                        "latitude": 37.7749,
                        "longitude": -122.4194,
                        "place_id": "mbx-123"
                    }
                ],
                "source": "mapbox",
                "cached": false
            }
        """.trimIndent()

        val client = mockClient(json)
        val response = client.post("/geocode") {
            setBody(ProxyService.GeocodeRequest(query = "Whole Foods"))
        }
        val decoded = response.body<ProxyService.GeocodeResponse>()

        assertEquals(1, decoded.results.size)
        assertEquals("Whole Foods", decoded.results[0].name)
        assertEquals(37.7749, decoded.results[0].latitude, 0.0001)
        assertEquals(-122.4194, decoded.results[0].longitude, 0.0001)
        assertEquals("mbx-123", decoded.results[0].placeId)
        assertTrue(!decoded.cached)
    }

    @Test
    fun `geocode request serializes proximity fields`() = runBlocking {
        val request = ProxyService.GeocodeRequest(
            query = "Target",
            proximityLat = 37.7,
            proximityLng = -122.4,
            limit = 3
        )
        val encoded = Json.encodeToString(ProxyService.GeocodeRequest.serializer(), request)
        assertTrue(encoded.contains("\"proximity_lat\":37.7"))
        assertTrue(encoded.contains("\"proximity_lng\":-122.4"))
        assertTrue(encoded.contains("\"limit\":3"))
    }

    @Test
    fun `route response parses waypoints_order`() = runBlocking {
        val json = """
            {
                "distance_meters": 2100.0,
                "duration_seconds": 450.0,
                "waypoints_order": [0, 2, 1],
                "geometry": "opt-polyline"
            }
        """.trimIndent()

        val client = mockClient(json)
        val response = client.post("/route") {
            setBody(ProxyService.RouteRequest(waypoints = listOf(listOf(37.0, -122.0))))
        }
        val decoded = response.body<ProxyService.RouteResponse>()

        assertEquals(2100.0, decoded.distanceMeters, 0.01)
        assertEquals(450.0, decoded.durationSeconds, 0.01)
        assertEquals(listOf(0, 2, 1), decoded.waypointsOrder)
        assertEquals("opt-polyline", decoded.geometry)
    }

    @Test
    fun `route request serializes waypoints correctly`() {
        val request = ProxyService.RouteRequest(
            waypoints = listOf(listOf(37.7749, -122.4194), listOf(37.7849, -122.4094)),
            optimize = true,
            profile = "mapbox/driving"
        )
        val encoded = Json.encodeToString(ProxyService.RouteRequest.serializer(), request)
        assertTrue(encoded.contains("\"waypoints\":[[37.7749,-122.4194],[37.7849,-122.4094]]"))
        assertTrue(encoded.contains("\"optimize\":true"))
    }
}
