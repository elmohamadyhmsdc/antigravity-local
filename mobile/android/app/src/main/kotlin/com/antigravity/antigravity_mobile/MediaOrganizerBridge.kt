package com.antigravity.antigravity_mobile

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Moves ORIGINAL media through MediaStore; row IDs and all app detections stay intact.
 * https://developer.android.com/training/data-storage/shared/media
 */
class MediaOrganizerBridge(private val activity: Activity) {
    companion object {
        private const val REQUEST = 18847
        private val moving = AtomicBoolean(false)
    }
    private val resolver = activity.applicationContext.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pending? = null
    private var closed = false
    private var awaitingPermission = false
    private data class Pending(val items: List<Map<*, *>>, val result: MethodChannel.Result,
        val results: MutableList<Map<String, Any?>> = mutableListOf(), var index: Int = 0,
        var retriedIndex: Int = -1)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canManageMedia" -> { result.success(canManage()); return }
            "requestManageMedia" -> {
                // The system page where the user switches "Media management" on for this app, once.
                try {
                    activity.startActivity(Intent(Settings.ACTION_REQUEST_MANAGE_MEDIA,
                        Uri.parse("package:" + activity.packageName)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (_: Exception) { result.success(false) }
                return
            }
        }
        if (call.method !in setOf("inspect", "preflight", "move")) { result.notImplemented(); return }
        val items = call.argument<List<Map<*, *>>>("items")
        if (items == null || items.size > 1000) {
            result.error("invalid_plan", "Choose at most 1000 files per batch.", null); return
        }
        if (Build.VERSION.SDK_INT < 29) {
            result.error("unsupported", "Moving originals requires Android 10 or newer.", null); return
        }
        if (call.method == "move" && !moving.compareAndSet(false, true)) {
            result.error("organizer_busy", "A media move is already in progress.", null); return
        }
        when (call.method) {
            "inspect" -> worker.execute {
                val rows = items.map { item ->
                    val id = item["assetId"] as? String ?: ""
                    try { read(uri(item)) ?: mapOf("assetId" to id, "error" to "missing") }
                    catch (_: Exception) { mapOf("assetId" to id, "error" to "unavailable") }
                }
                main.post { result.success(rows) }
            }
            "preflight" -> worker.execute {
                val rows = items.map(::check)
                main.post { result.success(rows) }
            }
            "move" -> {
                val request = Pending(items, result)
                pending = request
                worker.execute {
                    val checks = items.map(::check)
                    val writable = items.zip(checks).filter { it.second["status"] == "ready" }.map { uri(it.first) }
                    if (writable.isEmpty()) {
                        request.results.addAll(checks)
                        finish(request)
                    } else if (canManage()) {
                        // Granted "Media management": the system lets us move photos without a sheet.
                        process(request)
                    } else if (Build.VERSION.SDK_INT >= 30) {
                        try {
                            val grant = MediaStore.createWriteRequest(resolver, writable)
                            main.post {
                                if (closed) cancel(request) else try {
                                    awaitingPermission = true
                                    activity.startIntentSenderForResult(grant.intentSender, REQUEST, null, 0, 0, 0)
                                } catch (_: Exception) { cancel(request) }
                            }
                        } catch (_: Exception) { cancel(request) }
                    } else process(request)
                }
            }
        }
    }

    private fun canManage(): Boolean = Build.VERSION.SDK_INT >= 31 &&
        try { MediaStore.canManageMedia(activity.applicationContext) } catch (_: Exception) { false }

    private fun uri(item: Map<*, *>): Uri {
        val id = (item["assetId"] as? String)?.toLongOrNull() ?: error("Unsupported asset id")
        require(id > 0)
        val collection = when (item["kind"]) {
            "photo" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else -> error("Unsupported media kind")
        }
        return ContentUris.withAppendedId(collection, id)
    }

    private fun read(uri: Uri): Map<String, Any?>? {
        val columns = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.DATE_MODIFIED, MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.VOLUME_NAME)
        resolver.query(uri, columns, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            return mapOf("assetId" to ContentUris.parseId(uri).toString(), "name" to cursor.getString(0),
                "path" to (cursor.getString(1) ?: ""), "modifiedAt" to cursor.getLong(2) * 1000,
                "size" to cursor.getLong(3), "mimeType" to (cursor.getString(4) ?: ""),
                "volume" to (cursor.getString(5) ?: "external_primary"))
        }
        return null
    }

    private fun validName(value: String): Boolean = value.isNotBlank() && value != "." && value != ".." &&
        value.toByteArray(Charsets.UTF_8).size <= 240 && value.none { it.code < 32 || it in "/\\:*?\"<>|" }

    private fun validate(item: Map<*, *>) {
        val name = item["targetName"] as? String ?: error("Missing name")
        val path = item["targetPath"] as? String ?: error("Missing folder")
        require(validName(name))
        val segments = path.removeSuffix("/").split('/')
        require(path.endsWith('/') && segments.size in 3..6 && segments.first() == "DCIM" && segments.all(::validName))
    }

    private fun outcome(item: Map<*, *>, status: String, actual: Map<String, Any?>? = null, detail: String? = null): Map<String, Any?> =
        mapOf("assetId" to item["assetId"], "status" to status, "actual" to actual, "detail" to detail)

    private fun collision(item: Map<*, *>, actual: Map<String, Any?>): Boolean {
        val collection = MediaStore.Files.getContentUri(actual["volume"] as String)
        resolver.query(collection, arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? COLLATE NOCASE AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ? COLLATE NOCASE",
            arrayOf(item["targetName"] as String, item["targetPath"] as String), null)?.use { cursor ->
            while (cursor.moveToNext()) if (cursor.getLong(0).toString() != item["assetId"]) return true
        }
        return false
    }

    private fun check(item: Map<*, *>): Map<String, Any?> = try {
        validate(item)
        val actual = read(uri(item))
        when {
            actual == null -> outcome(item, "missing")
            actual["name"] == item["targetName"] && actual["path"] == item["targetPath"] -> outcome(item, "already", actual)
            actual["name"] != item["sourceName"] || actual["path"] != item["sourcePath"] ||
                actual["modifiedAt"] != (item["sourceModifiedAt"] as? Number)?.toLong() ||
                actual["size"] != (item["sourceSize"] as? Number)?.toLong() -> outcome(item, "stale", actual)
            collision(item, actual) -> outcome(item, "conflict", actual)
            else -> outcome(item, "ready", actual)
        }
    } catch (_: Exception) { outcome(item, "failed") }

    private fun process(request: Pending) {
        while (request.index < request.items.size) {
            val item = request.items[request.index]
            val checked = check(item)
            if (checked["status"] != "ready") {
                request.results.add(checked); request.index++; continue
            }
            try {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, item["targetName"] as String)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, item["targetPath"] as String)
                }
                val count = resolver.update(uri(item), values, null, null)
                val actual = read(uri(item))
                if (count != 1 || actual == null) request.results.add(outcome(item, "failed"))
                else request.results.add(outcome(item, "moved", actual,
                    if (actual["name"] != item["targetName"] || actual["path"] != item["targetPath"]) "system_adjusted_name" else null))
                request.index++
            } catch (error: SecurityException) {
                if (Build.VERSION.SDK_INT == 29 && error is RecoverableSecurityException && request.retriedIndex != request.index) {
                    request.retriedIndex = request.index
                    main.post {
                        if (closed) cancel(request) else try {
                            awaitingPermission = true
                            activity.startIntentSenderForResult(error.userAction.actionIntent.intentSender, REQUEST, null, 0, 0, 0)
                        } catch (_: Exception) { cancel(request) }
                    }
                    return
                }
                request.results.add(outcome(item, "denied")); request.index++
            } catch (_: Exception) {
                // The update could have succeeded before a provider/query error.
                // Reconcile the durable journal against MediaStore on the next attempt.
                request.results.add(outcome(item, "uncertain")); request.index++
            }
        }
        finish(request)
    }

    private fun finish(request: Pending) {
        main.post {
            if (pending !== request) return@post
            awaitingPermission = false
            pending = null
            moving.set(false)
            request.result.success(request.results)
        }
    }

    private fun cancel(request: Pending) {
        while (request.index < request.items.size) {
            request.results.add(outcome(request.items[request.index], "cancelled")); request.index++
        }
        finish(request)
    }

    fun onActivityResult(code: Int, resultCode: Int): Boolean {
        if (code != REQUEST) return false
        val request = pending ?: return true
        awaitingPermission = false
        if (resultCode == Activity.RESULT_OK) worker.execute { process(request) } else cancel(request)
        return true
    }

    fun close() {
        closed = true
        if (awaitingPermission) pending?.let { cancel(it) }
        // Active work finishes on the app-context resolver. A retained Flutter
        // engine can still receive its result after the Activity is removed.
        worker.shutdown()
    }
}
