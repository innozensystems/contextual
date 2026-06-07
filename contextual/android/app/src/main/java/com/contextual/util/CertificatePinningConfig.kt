package com.contextual.util

import okhttp3.CertificatePinner

object CertificatePinningConfig {

    /**
     * Parse a comma-separated list of certificate pins.
     * Each pin must be in the format `sha256/AAAA...`.
     * Empty or blank strings return an empty list.
     */
    fun parsePins(pinsCsv: String): List<String> {
        if (pinsCsv.isBlank()) return emptyList()
        return pinsCsv
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() && it.startsWith("sha256/") }
    }

    /**
     * Build an OkHttp CertificatePinner for the given hostname and pins.
     * Returns null if no valid pins are provided.
     */
    fun createPinner(hostname: String, pins: List<String>): CertificatePinner? {
        if (pins.isEmpty()) return null
        val builder = CertificatePinner.Builder()
        pins.forEach { builder.add(hostname, it) }
        return builder.build()
    }
}
