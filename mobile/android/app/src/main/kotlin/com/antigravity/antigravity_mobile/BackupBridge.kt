package com.antigravity.antigravity_mobile

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class BackupBridge(private val activity: Activity) {
    companion object {
        private const val SAVE_REQUEST = 18844
        private val worker = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
    }

    private val context = activity.applicationContext
    private var pendingSave: Pair<File, MethodChannel.Result>? = null

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        val roots = listOf(context.filesDir, context.cacheDir, File(context.applicationInfo.dataDir, "app_flutter"))
        require(roots.any { file.path.startsWith(it.canonicalPath + File.separator) })
        return file
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "save") {
            chooseDestination(call, result)
            return
        }
        if (call.method !in listOf("encrypt", "decrypt")) { result.notImplemented(); return }
        try {
            val source = privateFile(requireNotNull(call.argument<String>("source")))
            val target = privateFile(requireNotNull(call.argument<String>("target")))
            val password = requireNotNull(call.argument<String>("password")).toCharArray()
            worker.execute {
                try {
                    BackupCipher.transform(source, target, password, call.method == "encrypt")
                    main.post { result.success(true) }
                } catch (_: Exception) {
                    main.post { result.error("backup_crypto_failed", "The password is incorrect, the backup is damaged, or storage is unavailable.", null) }
                } finally { password.fill('\u0000') }
            }
        } catch (_: Exception) {
            result.error("backup_invalid_input", "Choose a private backup file and a new output path.", null)
        }
    }

    private fun chooseDestination(call: MethodCall, result: MethodChannel.Result) {
        if (pendingSave != null) {
            result.error("backup_save_busy", "A backup location is already being selected.", null)
            return
        }
        try {
            val source = privateFile(requireNotNull(call.argument<String>("source")))
            require(source.isFile && source.length() > 0)
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, source.name)
            }
            pendingSave = source to result
            activity.startActivityForResult(intent, SAVE_REQUEST)
        } catch (e: Exception) {
            pendingSave = null
            result.error("backup_save_failed", e.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE_REQUEST) return false
        val (source, result) = pendingSave ?: return true
        pendingSave = null
        if (resultCode == Activity.RESULT_CANCELED) {
            result.success(false)
            return true
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.error("backup_save_failed", "Android Files did not return a destination.", null)
            return true
        }

        val resolver = context.contentResolver
        worker.execute {
            try {
                source.inputStream().use { input ->
                    val output = checkNotNull(resolver.openOutputStream(uri)) {
                        "Could not open the backup destination."
                    }
                    output.use { input.copyTo(it) }
                }
                main.post { result.success(true) }
            } catch (e: Exception) {
                // Remove an incomplete document if its provider allows deletion.
                runCatching { DocumentsContract.deleteDocument(resolver, uri) }
                main.post { result.error("backup_save_failed", e.message, null) }
            }
        }
        return true
    }

    fun cancelPendingSave() {
        pendingSave?.second?.success(false)
        pendingSave = null
    }
}
