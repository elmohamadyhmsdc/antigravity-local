package com.antigravity.antigravity_mobile

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Matrix
import android.graphics.Rect
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Training export: cuts face/body crops out of the ORIGINAL photo or video frame at native
 * resolution (the stored crops are small previews). Photos are region-decoded, so a 100 MP
 * original is never held whole in memory. Originals are only read.
 */
class CropExportBridge(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    // Worker-thread only: what the last open() produced.
    private var decoder: BitmapRegionDecoder? = null
    private var descriptor: ParcelFileDescriptor? = null
    private var frame: Bitmap? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in listOf("open", "crop", "close")) { result.notImplemented(); return }
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "open" -> open(call)
                    "crop" -> crop(call)
                    else -> { release(); null }
                }
                main.post { result.success(value) }
            } catch (error: Throwable) {
                release()
                main.post { result.error("crop_export_failed", "The original could not be read on this phone.", null) }
            }
        }
    }

    private fun release() {
        try { decoder?.recycle() } catch (_: Exception) {}
        try { descriptor?.close() } catch (_: Exception) {}
        try { frame?.recycle() } catch (_: Exception) {}
        decoder = null; descriptor = null; frame = null
    }

    private fun id(call: MethodCall): Long {
        val id = call.argument<String>("assetId") ?: ""
        require(id.isNotEmpty() && id.all { it.isDigit() }) { "Not a MediaStore asset." }
        return id.toLong()
    }

    private fun open(call: MethodCall): Map<String, Any?>? {
        release()
        val asset = id(call)
        return if (call.argument<Boolean>("video") == true) {
            openVideo(asset, (call.argument<Number>("timeMs") ?: 0).toLong())
        } else {
            openPhoto(asset)
        }
    }

    private fun openPhoto(asset: Long): Map<String, Any?>? {
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, asset)
        val orientation = try {
            context.contentResolver.openInputStream(uri)?.use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } ?: 1
        } catch (_: Exception) { 1 }
        val pfd = context.contentResolver.openFileDescriptor(uri, "r") ?: return null
        return try {
            // Region decoding covers JPEG, PNG and WebP; other formats throw and count as unreadable.
            @Suppress("DEPRECATION")
            val d = BitmapRegionDecoder.newInstance(pfd.fileDescriptor, false)
            if (d == null) { pfd.close(); null } else {
                decoder = d
                descriptor = pfd
                mapOf("width" to d.width, "height" to d.height, "orientation" to orientation.coerceIn(1, 8))
            }
        } catch (_: Exception) { pfd.close(); null }
    }

    private fun openVideo(asset: Long, timeMs: Long): Map<String, Any?>? {
        val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, asset)
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(context, uri)
            // Same seek order as the scan, so the frame is the one the boxes were found in.
            var bitmap: Bitmap? = null
            for (option in listOf(MediaMetadataRetriever.OPTION_CLOSEST, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)) {
                try { bitmap = r.getFrameAtTime(timeMs * 1000, option) } catch (_: RuntimeException) {}
                if (bitmap != null) break
            }
            val b = bitmap ?: return null
            frame = b
            return mapOf("width" to b.width, "height" to b.height, "orientation" to 1)
        } finally { try { r.release() } catch (_: Exception) {} }
    }

    private fun crop(call: MethodCall): ByteArray? {
        fun int(name: String) = (call.argument<Number>(name) ?: throw IllegalArgumentException(name)).toInt()
        val rect = Rect(int("left"), int("top"), int("left") + int("width"), int("top") + int("height"))
        val outW = int("outWidth").coerceIn(1, 8192)
        val outH = int("outHeight").coerceIn(1, 8192)
        val quality = int("quality").coerceIn(50, 100)
        val orientation = int("orientation").coerceIn(1, 8)
        val source = region(rect, max(outW, outH)) ?: return null
        var upright: Bitmap = source
        try {
            matrixFor(orientation)?.let {
                upright = Bitmap.createBitmap(source, 0, 0, source.width, source.height, it, true)
                if (upright !== source) source.recycle()
            }
            val sized = scaleTo(upright, outW, outH)
            try {
                val bytes = ByteArrayOutputStream()
                return if (sized.compress(Bitmap.CompressFormat.JPEG, quality, bytes)) bytes.toByteArray() else null
            } finally { if (sized !== upright) sized.recycle() }
        } finally { upright.recycle() }
    }

    /** The stored pixels of [rect]; large regions are read at the smallest reduction that still covers [needed]. */
    private fun region(rect: Rect, needed: Int): Bitmap? {
        frame?.let { f ->
            val r = Rect(rect)
            if (!r.intersect(0, 0, f.width, f.height) || r.width() < 1 || r.height() < 1) return null
            return Bitmap.createBitmap(f, r.left, r.top, r.width(), r.height())
        }
        val d = decoder ?: return null
        val r = Rect(rect)
        if (!r.intersect(0, 0, d.width, d.height) || r.width() < 1 || r.height() < 1) return null
        var sample = 1
        while (max(r.width(), r.height()) / (sample * 2) >= needed) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return d.decodeRegion(r, options)
    }

    /** Matrix that turns stored pixels upright for EXIF orientation 2..8 (null for 1). */
    private fun matrixFor(orientation: Int): Matrix? {
        val m = Matrix()
        when (orientation) {
            2 -> m.setScale(-1f, 1f)
            3 -> m.setRotate(180f)
            4 -> { m.setRotate(180f); m.postScale(-1f, 1f) }
            5 -> { m.setRotate(90f); m.postScale(-1f, 1f) }
            6 -> m.setRotate(90f)
            7 -> { m.setRotate(-90f); m.postScale(-1f, 1f) }
            8 -> m.setRotate(-90f)
            else -> return null
        }
        return m
    }

    /** Halves repeatedly before the last step, so a big reduction does not alias. */
    private fun scaleTo(src: Bitmap, w: Int, h: Int): Bitmap {
        if (src.width == w && src.height == h) return src
        var current = src
        while (current.width / 2 >= w && current.height / 2 >= h) {
            val next = Bitmap.createScaledBitmap(
                current, (current.width / 2.0).roundToInt(), (current.height / 2.0).roundToInt(), true)
            if (current !== src) current.recycle()
            current = next
        }
        val out = Bitmap.createScaledBitmap(current, w, h, true)
        if (current !== src && current !== out) current.recycle()
        return out
    }
}
