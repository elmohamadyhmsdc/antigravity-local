package com.antigravity.antigravity_mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Uses app context so Activity removal cannot interrupt an ongoing export. */
class BackupBridge(private val context: Context) {
    companion object {
        private val worker = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
    }

    private fun privateFile(path: String): File {
        val file = File(path).canonicalFile
        val roots = listOf(context.filesDir, context.cacheDir, File(context.applicationInfo.dataDir, "app_flutter"))
        require(roots.any { file.path.startsWith(it.canonicalPath + File.separator) })
        return file
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
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
}
