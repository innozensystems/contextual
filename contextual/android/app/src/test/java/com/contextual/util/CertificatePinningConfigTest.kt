package com.contextual.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CertificatePinningConfigTest {

    @Test
    fun `parsePins returns empty for blank string`() {
        assertTrue(CertificatePinningConfig.parsePins("").isEmpty())
        assertTrue(CertificatePinningConfig.parsePins("   ").isEmpty())
    }

    @Test
    fun `parsePins splits comma separated values`() {
        val pins = CertificatePinningConfig.parsePins("sha256/abc, sha256/def ,sha256/ghi")
        assertEquals(listOf("sha256/abc", "sha256/def", "sha256/ghi"), pins)
    }

    @Test
    fun `parsePins filters invalid prefixes`() {
        val pins = CertificatePinningConfig.parsePins("sha256/valid, md5/invalid, sha256/also_valid")
        assertEquals(listOf("sha256/valid", "sha256/also_valid"), pins)
    }

    @Test
    fun `createPinner returns null for empty pins`() {
        assertNull(CertificatePinningConfig.createPinner("api.example.com", emptyList()))
    }

    @Test
    fun `createPinner builds pinner for valid pins`() {
        val pinner = CertificatePinningConfig.createPinner(
            "api.example.com",
            listOf("sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        )
        assertTrue(pinner != null)
    }
}
