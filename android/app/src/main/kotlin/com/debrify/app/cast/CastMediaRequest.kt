package com.debrify.app.cast

import android.net.Uri
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaTrack
import com.google.android.gms.common.images.WebImage
import java.net.URI
import java.util.Locale

internal class CastRequestException(
    val errorCode: String,
    message: String,
) : IllegalArgumentException(message)

data class CastTextTrackRequest(
    val id: Long,
    val url: String,
    val language: String,
    val label: String,
    val mimeType: String,
) {
    fun toMediaTrack(): MediaTrack =
        MediaTrack.Builder(id, MediaTrack.TYPE_TEXT)
            .setName(label)
            .setSubtype(MediaTrack.SUBTYPE_SUBTITLES)
            .setContentId(url)
            .setContentType(mimeType)
            .setLanguage(language)
            .build()
}

data class CastMediaRequest(
    val url: String,
    val mimeType: String?,
    val title: String?,
    val subtitle: String?,
    val seriesTitle: String?,
    val season: Int?,
    val episode: Int?,
    val posterUrl: String?,
    val backdropUrl: String?,
    val positionMs: Long?,
    val durationMs: Long?,
    val autoplay: Boolean,
    val isLive: Boolean,
    val headers: Map<String, String>,
    val textTracks: List<CastTextTrackRequest>,
) {
    val hasUnsupportedHeaders: Boolean
        get() = headers.isNotEmpty()

    fun toMediaInfo(): MediaInfo {
        val contentType = mimeType?.takeIf { it.isNotBlank() }
            ?: inferMimeType(url)
            ?: "application/octet-stream"
        val metadataType = when {
            !seriesTitle.isNullOrBlank() || season != null || episode != null ->
                MediaMetadata.MEDIA_TYPE_TV_SHOW
            else -> MediaMetadata.MEDIA_TYPE_GENERIC
        }
        val metadata = MediaMetadata(metadataType)
        title?.takeIf { it.isNotBlank() }?.let {
            metadata.putString(MediaMetadata.KEY_TITLE, it)
        }
        if (metadataType == MediaMetadata.MEDIA_TYPE_TV_SHOW) {
            seriesTitle?.takeIf { it.isNotBlank() }?.let {
                metadata.putString(MediaMetadata.KEY_SERIES_TITLE, it)
            }
            season?.takeIf { it >= 0 }?.let {
                metadata.putInt(MediaMetadata.KEY_SEASON_NUMBER, it)
            }
            episode?.takeIf { it >= 0 }?.let {
                metadata.putInt(MediaMetadata.KEY_EPISODE_NUMBER, it)
            }
        } else {
            subtitle?.takeIf { it.isNotBlank() }?.let {
                metadata.putString(MediaMetadata.KEY_SUBTITLE, it)
            }
        }
        addImageIfHttp(metadata, posterUrl)
        if (backdropUrl != posterUrl) addImageIfHttp(metadata, backdropUrl)

        val builder = MediaInfo.Builder(url)
            .setContentUrl(url)
            .setContentType(contentType)
            .setStreamType(
                if (isLive) MediaInfo.STREAM_TYPE_LIVE
                else MediaInfo.STREAM_TYPE_BUFFERED,
            )
            .setMetadata(metadata)
        if (textTracks.isNotEmpty()) {
            builder.setMediaTracks(textTracks.map(CastTextTrackRequest::toMediaTrack))
        }
        durationMs?.takeIf { it >= 0 && !isLive }?.let(builder::setStreamDuration)
        return builder.build()
    }

    companion object {
        fun fromMap(raw: Map<*, *>): CastMediaRequest {
            val url = (raw["url"] as? String)?.trim().orEmpty()
            if (!isDirectHttpUrl(url)) {
                throw CastRequestException(
                    "CAST_INVALID_URL",
                    "Google Cast requires a direct HTTP or HTTPS media URL.",
                )
            }

            val headers = linkedMapOf<String, String>()
            (raw["headers"] as? Map<*, *>)?.forEach { (key, value) ->
                val name = key?.toString()?.trim().orEmpty()
                val headerValue = value?.toString()?.trim().orEmpty()
                if (name.isNotEmpty() && headerValue.isNotEmpty()) {
                    headers[name] = headerValue
                }
            }

            val textTracks = (raw["textTracks"] as? List<*>)
                ?.mapNotNull { item ->
                    val map = item as? Map<*, *> ?: return@mapNotNull null
                    val id = (map["id"] as? Number)?.toLong() ?: return@mapNotNull null
                    val trackUrl = (map["url"] as? String)?.trim().orEmpty()
                    val language = (map["language"] as? String)?.trim().orEmpty()
                    val label = (map["label"] as? String)?.trim().orEmpty()
                    val type = (map["mimeType"] as? String)?.trim().orEmpty()
                    if (!isDirectHttpUrl(trackUrl) ||
                        !type.equals("text/vtt", ignoreCase = true) ||
                        language.isEmpty()
                    ) {
                        return@mapNotNull null
                    }
                    CastTextTrackRequest(
                        id = id,
                        url = trackUrl,
                        language = language,
                        label = label.ifEmpty { language },
                        mimeType = "text/vtt",
                    )
                }
                ?.distinctBy { it.id }
                ?: emptyList()

            return CastMediaRequest(
                url = url,
                mimeType = (raw["mimeType"] as? String)?.trim()?.ifEmpty { null },
                title = (raw["title"] as? String)?.trim()?.ifEmpty { null },
                subtitle = (raw["subtitle"] as? String)?.trim()?.ifEmpty { null },
                seriesTitle = (raw["seriesTitle"] as? String)?.trim()?.ifEmpty { null },
                season = (raw["season"] as? Number)?.toInt(),
                episode = (raw["episode"] as? Number)?.toInt(),
                posterUrl = (raw["posterUrl"] as? String)?.trim()?.ifEmpty { null },
                backdropUrl = (raw["backdropUrl"] as? String)?.trim()?.ifEmpty { null },
                positionMs = positiveOrZero(raw["positionMs"]),
                durationMs = positiveOrZero(raw["durationMs"]),
                autoplay = raw["autoplay"] as? Boolean ?: true,
                isLive = raw["isLive"] as? Boolean ?: false,
                headers = headers,
                textTracks = textTracks,
            )
        }

        fun isDirectHttpUrl(value: String): Boolean = try {
            val parsed = URI(value)
            val scheme = parsed.scheme?.lowercase(Locale.US)
            (scheme == "http" || scheme == "https") && !parsed.host.isNullOrBlank()
        } catch (_: Exception) {
            false
        }

        fun inferMimeType(value: String): String? {
            val path = try {
                URI(value).path?.lowercase(Locale.US).orEmpty()
            } catch (_: Exception) {
                value.substringBefore('?').lowercase(Locale.US)
            }
            return when {
                path.endsWith(".m3u8") -> "application/x-mpegURL"
                path.endsWith(".mpd") -> "application/dash+xml"
                path.endsWith(".mp4") || path.endsWith(".m4v") -> "video/mp4"
                path.endsWith(".webm") -> "video/webm"
                path.endsWith(".mp3") -> "audio/mpeg"
                path.endsWith(".m4a") -> "audio/mp4"
                else -> null
            }
        }

        private fun positiveOrZero(value: Any?): Long? {
            val number = value as? Number ?: return null
            return number.toLong().takeIf { it >= 0 }
        }

        private fun addImageIfHttp(metadata: MediaMetadata, value: String?) {
            val url = value?.trim()?.takeIf { isDirectHttpUrl(it) } ?: return
            metadata.addImage(WebImage(Uri.parse(url)))
        }
    }
}
