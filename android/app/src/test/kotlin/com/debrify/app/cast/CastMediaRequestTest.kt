package com.debrify.app.cast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CastMediaRequestTest {
    @Test
    fun parsesDirectHttpRequestAndPosition() {
        val request = CastMediaRequest.fromMap(
            mapOf(
                "url" to "https://media.example.test/movie.mp4",
                "positionMs" to 42_000,
                "durationMs" to 120_000,
                "title" to "Movie",
            ),
        )
        assertEquals("https://media.example.test/movie.mp4", request.url)
        assertEquals(42_000L, request.positionMs)
        assertEquals(120_000L, request.durationMs)
        assertFalse(request.hasUnsupportedHeaders)
    }

    @Test(expected = CastRequestException::class)
    fun rejectsNonHttpUrl() {
        CastMediaRequest.fromMap(
            mapOf("url" to "magnet:?xt=urn:btih:123"),
        )
    }

    @Test
    fun flagsHeadersWithoutExposingValuesInTheClassification() {
        val request = CastMediaRequest.fromMap(
            mapOf(
                "url" to "https://media.example.test/movie.mp4",
                "headers" to mapOf("Authorization" to "test-secret"),
            ),
        )
        assertTrue(request.hasUnsupportedHeaders)
        assertEquals(1, request.headers.size)
    }

    @Test
    fun optionalMetadataAndUnknownTimesRemainOptional() {
        val request = CastMediaRequest.fromMap(
            mapOf("url" to "https://media.example.test/live.m3u8"),
        )
        assertNull(request.subtitle)
        assertNull(request.posterUrl)
        assertNull(request.positionMs)
        assertNull(request.durationMs)
    }

    @Test
    fun infersPriorityMimeTypes() {
        assertEquals(
            "application/x-mpegURL",
            CastMediaRequest.inferMimeType("https://example.test/master.m3u8"),
        )
        assertEquals(
            "application/dash+xml",
            CastMediaRequest.inferMimeType("https://example.test/manifest.mpd"),
        )
        assertEquals(
            "video/mp4",
            CastMediaRequest.inferMimeType("https://example.test/movie.mp4"),
        )
        assertNull(
            CastMediaRequest.inferMimeType("https://example.test/download/123"),
        )
    }
}
