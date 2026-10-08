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
    fun parsesReceiverReachableWebVttTrack() {
        val request = CastMediaRequest.fromMap(
            mapOf(
                "url" to "https://media.example.test/movie.mp4",
                "textTracks" to listOf(
                    mapOf(
                        "id" to 1001,
                        "url" to "https://subs.example.test/es.vtt",
                        "language" to "es-MX",
                        "label" to "Spanish",
                        "mimeType" to "text/vtt",
                    ),
                ),
            ),
        )
        assertEquals(1, request.textTracks.size)
        assertEquals(1001L, request.textTracks.single().id)
        assertEquals("es-MX", request.textTracks.single().language)
        assertEquals("text/vtt", request.textTracks.single().mimeType)
    }

    @Test
    fun dropsUnsupportedOrReceiverUnreachableTextTracks() {
        val request = CastMediaRequest.fromMap(
            mapOf(
                "url" to "https://media.example.test/movie.mp4",
                "textTracks" to listOf(
                    mapOf(
                        "id" to 1001,
                        "url" to "https://subs.example.test/es.srt",
                        "language" to "es",
                        "label" to "Spanish SRT",
                        "mimeType" to "application/x-subrip",
                    ),
                    mapOf(
                        "id" to 1002,
                        "url" to "file:///data/user/0/com.debrify.app/cache/es.vtt",
                        "language" to "es",
                        "label" to "Private VTT",
                        "mimeType" to "text/vtt",
                    ),
                ),
            ),
        )
        assertTrue(request.textTracks.isEmpty())
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
