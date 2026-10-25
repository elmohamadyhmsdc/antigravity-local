package com.antigravity.antigravity_mobile

import android.app.Activity
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import io.flutter.plugin.common.MethodCall
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import kotlin.math.max
import kotlin.math.roundToInt

/** Decode bounded, small preview frames locally; no source video is uploaded for face discovery. */
object VideoFrameSampler {
    fun sample(activity: Activity, call: MethodCall, active: () -> Boolean = { true }): List<ByteArray> {
        val file = File(call.argument<String>("path") ?: "").canonicalFile
        val roots = listOf(activity.cacheDir, activity.filesDir) + activity.externalCacheDirs.filterNotNull()
        require(roots.any { file.path.startsWith(it.canonicalPath + File.separator) } && file.isFile) {
            "Choose a video from this device first."
        }
        val count = (call.argument<Number>("count")?.toInt() ?: 12).coerceIn(1, 12)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?: throw IOException("Unreadable duration")
            val start = (call.argument<Number>("startMs")?.toLong() ?: 0).coerceAtLeast(0)
            val end = (call.argument<Number>("endMs")?.toLong() ?: duration).coerceAtMost(duration)
            require(start < end) { "Choose a valid video range." }
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 1280
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 720
            // >=1600 px lets the server use its high-resolution face detector
            // pass; 1280 px previews excluded that pass and missed small faces.
            val scale = (1920.0 / max(width, height)).coerceAtMost(1.0)
            val output = mutableListOf<ByteArray>()
            repeat(count) { index ->
                if (Thread.currentThread().isInterrupted || !active()) throw IOException("Video sampling cancelled")
                val timeMs = start + ((end - start - 1) * index / max(1, count - 1))
                var decoded: Bitmap? = null
                for (option in listOf(MediaMetadataRetriever.OPTION_CLOSEST, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)) {
                    try {
                        decoded = if (Build.VERSION.SDK_INT >= 27) {
                            retriever.getScaledFrameAtTime(timeMs * 1000, option,
                                max(1, (width * scale).roundToInt()), max(1, (height * scale).roundToInt()))
                        } else {
                            retriever.getFrameAtTime(timeMs * 1000, option)
                        }
                    } catch (_: RuntimeException) {
                        // Hardware decoders may reject exact seeks. Try a sync
                        // frame, keeping any other readable frames in the clip.
                    }
                    if (decoded != null) break
                }
                val bitmap = decoded
                if (bitmap != null) {
                    try {
                        val ratio = (1920.0 / max(bitmap.width, bitmap.height)).coerceAtMost(1.0)
                        val frame = if (ratio < 1) Bitmap.createScaledBitmap(bitmap,
                            max(1, (bitmap.width * ratio).roundToInt()), max(1, (bitmap.height * ratio).roundToInt()), true) else bitmap
                        try {
                            val bytes = ByteArrayOutputStream()
                            if (frame.compress(Bitmap.CompressFormat.JPEG, 88, bytes)) output.add(bytes.toByteArray())
                        } finally { if (frame !== bitmap) frame.recycle() }
                    } finally { bitmap.recycle() }
                }
            }
            if (output.isEmpty()) throw IOException("No readable frames")
            return output
        } finally { retriever.release() }
    }
}
