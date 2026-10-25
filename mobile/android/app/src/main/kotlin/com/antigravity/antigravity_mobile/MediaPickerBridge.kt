package com.antigravity.antigravity_mobile

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Explicit app chooser: do not let a saved Photos default hide other galleries. */
class MediaPickerBridge(private val activity: Activity) {
    private val requestCode = 18843
    private var pending: MethodChannel.Result? = null
    private var multiple = false
    private val frameRequests = mutableSetOf<MethodChannel.Result>()
    private val frameGeneration = AtomicInteger()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "sampleVideoFrames") {
            val generation = frameGeneration.incrementAndGet()
            frameRequests.add(result)
            worker.execute {
                try {
                    val frames = VideoFrameSampler.sample(activity, call) { generation == frameGeneration.get() }
                    main.post { if (frameRequests.remove(result)) result.success(frames) }
                } catch (error: Exception) {
                    main.post { if (frameRequests.remove(result)) result.error("video_frames_failed", "The video frames could not be read.", null) }
                }
            }
            return
        }
        if (call.method != "pickGalleryMedia") { result.notImplemented(); return }
        if (pending != null) {
            result.error("picker_busy", "A media picker is already open.", null)
            return
        }
        multiple = call.argument<Boolean>("multiple") == true
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "*/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pending = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent.createChooser(intent, call.argument<String>("title")), requestCode)
        } catch (error: Exception) {
            pending = null
            result.error("picker_unavailable", "No compatible gallery app is available.", null)
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val result = pending ?: return true
        val uris = mutableListOf<android.net.Uri>()
        data?.clipData?.let { clip -> repeat(clip.itemCount) { uris.add(clip.getItemAt(it).uri) } }
        if (uris.isEmpty()) data?.data?.let(uris::add)
        if (resultCode != Activity.RESULT_OK || uris.isEmpty()) {
            pending = null
            result.success(null)
            return true
        }
        worker.execute {
            val created = mutableListOf<File>()
            try {
                require(uris.size <= 20) { "Choose at most 20 files at a time." }
                val resolver = activity.contentResolver
                val picked = uris.distinct().map { uri ->
                val mime = resolver.getType(uri).orEmpty()
                if (!mime.startsWith("image/") && !mime.startsWith("video/")) {
                    throw IOException("Choose a photo or video.")
                }
                val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
                    ?.takeIf { it.matches(Regex("[a-zA-Z0-9]{1,10}")) } ?: "bin"
                val file = File.createTempFile("reface-gallery-", ".$extension", activity.cacheDir)
                created.add(file)
                val input = resolver.openInputStream(uri) ?: throw IOException("Unreadable media")
                input.use { source -> file.outputStream().use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        if (Thread.currentThread().isInterrupted) throw IOException("Picker closed")
                        val count = source.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                } }
                mapOf("path" to file.absolutePath, "mimeType" to mime)
                }
                main.post {
                    if (pending === result) {
                        pending = null
                        result.success(if (multiple) picked else picked.first())
                    } else {
                        created.forEach { it.delete() }
                    }
                }
            } catch (error: Exception) {
                created.forEach { it.delete() }
                main.post {
                    if (pending === result) {
                        pending = null
                        result.error("media_read_failed", "The selected photo or video could not be read.", null)
                    }
                }
            }
        }
        return true
    }

    fun close() {
        frameGeneration.incrementAndGet()
        pending?.success(null)
        pending = null
        frameRequests.forEach { it.error("video_frames_cancelled", "Video sampling was cancelled.", null) }
        frameRequests.clear()
        worker.shutdownNow()
    }
}
