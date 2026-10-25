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

/** Explicit app chooser: do not let a saved Photos default hide other galleries. */
class MediaPickerBridge(private val activity: Activity) {
    private val requestCode = 18843
    private var pending: MethodChannel.Result? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pickGalleryMedia") { result.notImplemented(); return }
        if (pending != null) {
            result.error("picker_busy", "A media picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "*/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
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
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(null)
            return true
        }
        worker.execute {
            var target: File? = null
            try {
                val resolver = activity.contentResolver
                val mime = resolver.getType(uri).orEmpty()
                if (!mime.startsWith("image/") && !mime.startsWith("video/")) {
                    throw IOException("Choose a photo or video.")
                }
                val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
                    ?.takeIf { it.matches(Regex("[a-zA-Z0-9]{1,10}")) } ?: "bin"
                val file = File.createTempFile("reface-gallery-", ".$extension", activity.cacheDir)
                target = file
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
                main.post {
                    if (pending === result) {
                        pending = null
                        result.success(mapOf("path" to file.absolutePath, "mimeType" to mime))
                    } else {
                        file.delete()
                    }
                }
            } catch (error: Exception) {
                target?.delete()
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
        pending?.success(null)
        pending = null
        worker.shutdownNow()
    }
}
