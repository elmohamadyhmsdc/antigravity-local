package com.antigravity.antigravity_mobile

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Moves ORIGINAL media; row IDs and all app detections stay intact.
 *
 * With "All files access" a move is a plain file rename: any folder (the top-level "Your Gallery"),
 * no system sheet, and it works with the app in the background. Without it, a move is a MediaStore
 * update inside DCIM/Your Gallery, which needs "Media management" or one system sheet per batch.
 * https://developer.android.com/training/data-storage/shared/media
 *
 * One instance lives as long as the retained Flutter engine. [activity] is attached while one exists,
 * so a scan that finishes with the screen off can still move files.
 */
class MediaOrganizerBridge(context: Context) {
    companion object {
        private const val REQUEST = 18847
        private val moving = AtomicBoolean(false)
    }
    private val appContext = context.applicationContext
    private val resolver = appContext.contentResolver
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pending? = null
    private var awaitingPermission = false
    /** The Activity that can show a system sheet; null while the app has none. */
    @Volatile var activity: Activity? = null
    /** The Activity is on screen (MainActivity onResume/onPause). Android silently drops a system sheet
     *  started from the background, and the move would then wait for an answer that never comes. */
    @Volatile var onScreen = false
    private data class Pending(val items: List<Map<*, *>>, val result: MethodChannel.Result,
        val results: MutableList<Map<String, Any?>> = mutableListOf(), var index: Int = 0,
        var retriedIndex: Int = -1)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Either access means "moves need no sheet".
            "canManageMedia" -> { result.success(allFiles() || canManage()); return }
            "hasAllFilesAccess" -> { result.success(allFiles()); return }
            "requestManageMedia" -> {
                // The system page where the user switches "Media management" on for this app, once.
                result.success(openSettings(Settings.ACTION_REQUEST_MANAGE_MEDIA, 31)); return
            }
            "requestAllFilesAccess" -> {
                // "All files access": the top-level Your Gallery folder, its .json files, moves with no sheet.
                result.success(openSettings(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, 30)); return
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
                    try { read(uri(item))?.let(::visible) ?: mapOf("assetId" to id, "error" to "missing") }
                    catch (_: Exception) { mapOf("assetId" to id, "error" to "unavailable") }
                }
                main.post { result.success(rows) }
            }
            "preflight" -> worker.execute {
                val rows = items.map(::check)
                main.post { result.success(rows.map(::reply)) }
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
                    } else if (allFiles() || canManage()) {
                        // No sheet: "All files access" renames files, "Media management" updates MediaStore.
                        process(request)
                    } else if (Build.VERSION.SDK_INT >= 30) {
                        try {
                            val grant = MediaStore.createWriteRequest(resolver, writable)
                            main.post { ask(request) { it.startIntentSenderForResult(grant.intentSender, REQUEST, null, 0, 0, 0) } }
                        } catch (_: Exception) { cancel(request) }
                    } else process(request)
                }
            }
        }
    }

    /** Shows a system sheet, or cancels the batch when there is no visible Activity to show it on. */
    private fun ask(request: Pending, show: (Activity) -> Unit) {
        val host = activity
        if (host == null || !onScreen) { cancel(request); return }
        try {
            awaitingPermission = true
            show(host)
        } catch (_: Exception) { awaitingPermission = false; cancel(request) }
    }

    private fun canManage(): Boolean = Build.VERSION.SDK_INT >= 31 &&
        try { MediaStore.canManageMedia(appContext) } catch (_: Exception) { false }

    private fun allFiles(): Boolean = Build.VERSION.SDK_INT >= 30 &&
        try { Environment.isExternalStorageManager() } catch (_: Exception) { false }

    private fun openSettings(action: String, minSdk: Int): Boolean {
        if (Build.VERSION.SDK_INT < minSdk) return false
        val host: Context = activity ?: appContext
        return try {
            host.startActivity(Intent(action, Uri.parse("package:" + appContext.packageName))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true
        } catch (_: Exception) {
            if (action != Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION) false else try {
                // Some builds only offer the list of apps, not the per-app page.
                host.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true
            } catch (_: Exception) { false }
        }
    }

    private fun uri(item: Map<*, *>): Uri {
        val id = (item["assetId"] as? String)?.toLongOrNull() ?: error("Unsupported asset id")
        require(id > 0)
        return ContentUris.withAppendedId(collection(item), id)
    }

    private fun collection(item: Map<*, *>): Uri = when (item["kind"]) {
        "photo" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        else -> error("Unsupported media kind")
    }

    /** MediaStore's view of one file; "file" is its absolute path, used here only and never sent to Dart. */
    private fun read(uri: Uri): Map<String, Any?>? {
        @Suppress("DEPRECATION")
        val columns = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.DATE_MODIFIED, MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.VOLUME_NAME, MediaStore.MediaColumns.DATA)
        resolver.query(uri, columns, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            return mapOf("assetId" to ContentUris.parseId(uri).toString(), "name" to cursor.getString(0),
                "path" to (cursor.getString(1) ?: ""), "modifiedAt" to cursor.getLong(2) * 1000,
                "size" to cursor.getLong(3), "mimeType" to (cursor.getString(4) ?: ""),
                "volume" to (cursor.getString(5) ?: "external_primary"), "file" to cursor.getString(6))
        }
        return null
    }

    private fun visible(info: Map<String, Any?>): Map<String, Any?> = info - "file"

    private fun reply(row: Map<String, Any?>): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        val actual = row["actual"] as? Map<String, Any?>
        return if (actual == null) row else row + ("actual" to visible(actual))
    }

    private fun validName(value: String): Boolean = value.isNotBlank() && value != "." && value != ".." &&
        value.toByteArray(Charsets.UTF_8).size <= 240 && value.none { it.code < 32 || it in "/\\:*?\"<>|" }

    private fun validate(item: Map<*, *>) {
        val name = item["targetName"] as? String ?: error("Missing name")
        val path = item["targetPath"] as? String ?: error("Missing folder")
        require(validName(name))
        val segments = path.removeSuffix("/").split('/')
        // DCIM/Your Gallery/... (a MediaStore update) or, with All files access, the top-level Your Gallery/...
        val dcim = segments.size in 3..6 && segments[0] == "DCIM" && segments[1] == "Your Gallery"
        val top = allFiles() && segments.size in 2..5 && segments[0] == "Your Gallery"
        require(path.endsWith('/') && (dcim || top) && segments.all(::validName))
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
                if (allFiles()) {
                    @Suppress("UNCHECKED_CAST")
                    request.results.add(renameFile(item, checked["actual"] as Map<String, Any?>))
                    request.index++; continue
                }
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
                    main.post { ask(request) { it.startIntentSenderForResult(error.userAction.actionIntent.intentSender, REQUEST, null, 0, 0, 0) } }
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

    /** A file-system rename (All files access). Android's media provider sees the rename and keeps the row,
     *  so the asset id and every detection stay valid. If the row is ever re-created instead, the result
     *  carries the new id (detail "new_asset_id") and the app rewrites its record. */
    private fun renameFile(item: Map<*, *>, actual: Map<String, Any?>): Map<String, Any?> {
        val sourcePath = actual["file"] as? String ?: return outcome(item, "failed", detail = "no_file_path")
        val relative = (actual["path"] as String) + (actual["name"] as String)
        if (!sourcePath.endsWith("/$relative")) return outcome(item, "failed", detail = "unexpected_file_path")
        val root = sourcePath.removeSuffix(relative)
        val source = File(sourcePath)
        val folder = File(root + (item["targetPath"] as String))
        val target = File(folder, item["targetName"] as String)
        if (!source.isFile) return outcome(item, "missing")
        if (target.exists()) return outcome(item, "conflict", actual)
        if (!folder.isDirectory && !folder.mkdirs()) return outcome(item, "failed", detail = "cannot_create_folder")
        if (!source.renameTo(target)) return outcome(item, "failed", detail = "rename_refused")
        read(uri(item))?.let { now -> if (now["file"] == target.path) return outcome(item, "moved", now) }
        // The provider has not caught up (or dropped the row): index both paths, then look again.
        val scanned = CountDownLatch(1)
        MediaScannerConnection.scanFile(appContext, arrayOf(source.path, target.path), null) { path, _ ->
            if (path == target.path) scanned.countDown()
        }
        scanned.await(10, TimeUnit.SECONDS)
        read(uri(item))?.let { now -> if (now["file"] == target.path) return outcome(item, "moved", now) }
        @Suppress("DEPRECATION")
        resolver.query(collection(item), arrayOf(MediaStore.MediaColumns._ID), "${MediaStore.MediaColumns.DATA} = ?",
            arrayOf(target.path), null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                read(ContentUris.withAppendedId(collection(item), cursor.getLong(0)))?.let { moved ->
                    return outcome(item, "moved", moved, "new_asset_id")
                }
            }
        }
        // The file is at the target; the next Organize run reconciles the journal.
        return outcome(item, "uncertain")
    }

    private fun finish(request: Pending) {
        main.post {
            if (pending !== request) return@post
            awaitingPermission = false
            pending = null
            moving.set(false)
            request.result.success(request.results.map(::reply))
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

    /** The Activity is going away; the bridge stays with the retained engine. A sheet it was showing
     *  can no longer answer, so that batch is cancelled. */
    fun detach(host: Activity) {
        if (activity !== host) return
        activity = null
        onScreen = false
        if (awaitingPermission) pending?.let { cancel(it) }
    }
}
