package com.antigravity.antigravity_mobile

import android.app.Activity
import android.app.KeyguardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class SecurityBridge(private val activity: Activity) {
    companion object { private var secureEnabled = false }
    private var pending: MethodChannel.Result? = null
    private val requestCode = 18842

    fun restoreWindow() {
        if (secureEnabled) activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    fun cancelPending() {
        pending?.success(false)
        pending = null
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "secure" -> {
                secureEnabled = call.argument<Boolean>("enabled") == true
                restoreWindow()
                result.success(true)
            }
            "authenticate" -> {
                val manager = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                if (!manager.isDeviceSecure || pending != null) { result.success(false); return }
                @Suppress("DEPRECATION")
                val intent = manager.createConfirmDeviceCredentialIntent(call.argument<String>("title"), call.argument<String>("body"))
                if (intent == null) { result.success(false); return }
                pending = result
                @Suppress("DEPRECATION")
                activity.startActivityForResult(intent, requestCode)
            }
            "exportMedia" -> {
                if (Build.VERSION.SDK_INT < 29) { result.success(false); return }
                val source = File(call.argument<String>("path") ?: "").canonicalFile
                if (!source.path.startsWith(activity.filesDir.canonicalPath + File.separator)) {
                    result.error("invalid_path", "The file must be in private app storage.", null); return
                }
                val mime = call.argument<String>("mime") ?: ""
                if (mime !in listOf("image/png", "image/jpeg", "video/mp4")) {
                    result.error("invalid_type", "Choose a photo or video.", null); return
                }
                val video = mime == "video/mp4"
                val collection = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                val extension = if (video) "mp4" else if (mime == "image/png") "png" else "jpg"
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, "Antigravity-${System.currentTimeMillis()}.$extension")
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, if (video) "Movies/Antigravity" else "Pictures/Antigravity")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = activity.contentResolver
                val uri = resolver.insert(collection, values)
                if (uri == null) { result.error("export_failed", "Could not create a gallery item.", null); return }
                // Large videos must not block Android's UI thread.
                Thread {
                    try {
                        resolver.openOutputStream(uri)!!.use { output -> source.inputStream().use { it.copyTo(output) } }
                        resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                        activity.runOnUiThread { result.success(true) }
                    } catch (error: Exception) {
                        resolver.delete(uri, null, null)
                        activity.runOnUiThread { result.error("export_failed", "The result could not be saved to the gallery.", null) }
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(code: Int, resultCode: Int): Boolean {
        if (code != requestCode) return false
        pending?.success(resultCode == Activity.RESULT_OK)
        pending = null
        return true
    }
}
