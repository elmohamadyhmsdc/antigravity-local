package com.antigravity.antigravity_mobile

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Library scan: decode the sampled frames of a MediaStore video on the phone, so only
 * small JPEGs cross the Wi-Fi instead of the whole video file.
 */
class VideoScanBridge(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    // Worker-thread only: the open video, reused across frame batches of one scan.
    private var openAsset: String? = null
    private var retriever: MediaMetadataRetriever? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in listOf("probe", "frames", "close")) { result.notImplemented(); return }
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "probe" -> probe(asset(call))
                    "frames" -> frames(asset(call), call.argument<List<Number>>("timesMs").orEmpty(),
                        (call.argument<Number>("maxSide")?.toInt() ?: 2048).coerceIn(256, 4096))
                    else -> { release(); null }
                }
                main.post { result.success(value) }
            } catch (error: Exception) {
                release()
                main.post { result.error("video_scan_failed", "The video could not be read on this phone.", null) }
            }
        }
    }

    private fun asset(call: MethodCall): String {
        val id = call.argument<String>("assetId") ?: ""
        require(id.isNotEmpty() && id.all { it.isDigit() }) { "Not a MediaStore video." }
        return id
    }

    private fun uri(asset: String) =
        ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, asset.toLong())

    private fun open(asset: String): MediaMetadataRetriever {
        retriever?.takeIf { openAsset == asset }?.let { return it }
        release()
        return MediaMetadataRetriever().also {
            it.setDataSource(context, uri(asset))
            retriever = it
            openAsset = asset
        }
    }

    private fun release() {
        try { retriever?.release() } catch (_: Exception) {}
        retriever = null
        openAsset = null
    }

    private fun probe(asset: String): Map<String, Any?> {
        val r = open(asset)
        fun meta(key: Int) = r.extractMetadata(key)
        val duration = meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        val frameCount = if (Build.VERSION.SDK_INT >= 28)
            meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toLongOrNull() else null
        var fps: Double? = null
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(context, uri(asset), null)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                if (format.getString(MediaFormat.KEY_MIME)?.startsWith("video/") != true) continue
                if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                    fps = try { format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble() }
                    catch (_: ClassCastException) { format.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble() }
                }
                break
            }
        } catch (_: Exception) {
            // The frame count below still gives a rate for most containers.
        } finally { extractor.release() }
        if ((fps == null || fps <= 0) && frameCount != null && frameCount > 0 && duration > 0) {
            fps = frameCount * 1000.0 / duration
        }
        return mapOf("durationMs" to duration, "frameCount" to frameCount, "fps" to fps,
            "width" to meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull(),
            "height" to meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull())
    }

    /** One JPEG per requested time (null when that frame cannot be decoded), long side <= maxSide. */
    private fun frames(asset: String, times: List<Number>, maxSide: Int): List<ByteArray?> {
        val r = open(asset)
        return times.take(8).map { time ->
            var decoded: Bitmap? = null
            for (option in listOf(MediaMetadataRetriever.OPTION_CLOSEST, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)) {
                try {
                    // A square box keeps the aspect ratio and works for rotated videos too.
                    decoded = if (Build.VERSION.SDK_INT >= 27) {
                        r.getScaledFrameAtTime(time.toLong() * 1000, option, maxSide, maxSide)
                    } else {
                        r.getFrameAtTime(time.toLong() * 1000, option)
                    }
                } catch (_: RuntimeException) {
                    // Some hardware decoders reject exact seeks; fall back to the sync frame.
                }
                if (decoded != null) break
            }
            decoded?.let { bitmap ->
                try {
                    val ratio = (maxSide.toDouble() / max(bitmap.width, bitmap.height)).coerceAtMost(1.0)
                    val frame = if (ratio < 1) Bitmap.createScaledBitmap(bitmap,
                        max(1, (bitmap.width * ratio).roundToInt()), max(1, (bitmap.height * ratio).roundToInt()), true) else bitmap
                    try {
                        val bytes = ByteArrayOutputStream()
                        if (frame.compress(Bitmap.CompressFormat.JPEG, 90, bytes)) bytes.toByteArray() else null
                    } finally { if (frame !== bitmap) frame.recycle() }
                } finally { bitmap.recycle() }
            }
        }
    }
}
