package com.antigravity.antigravity_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.content.Intent

class MainActivity : FlutterActivity() {
    companion object { private const val ENGINE_ID = "antigravity_work_engine" }
    private val security by lazy { SecurityBridge(this) }
    private var securityChannel: MethodChannel? = null
    private val mediaOrganizer by lazy { MediaOrganizerBridge(this) }
    private var mediaOrganizerChannel: MethodChannel? = null
    private val mediaPicker by lazy { MediaPickerBridge(this) }
    private var mediaPickerChannel: MethodChannel? = null
    private val wakeLockBridge by lazy { WakeLockBridge(applicationContext) }
    // The foreground service protects the process; retain the actual Dart work
    // as well when Android removes the Activity (for example, a task swipe).
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(ENGINE_ID)
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
        security.allowScreenCapture()
        securityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/security").also {
            it.setMethodCallHandler(security::handle)
        }
        mediaOrganizerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/media_organizer").also {
            it.setMethodCallHandler(mediaOrganizer::handle)
        }
        val appContext = applicationContext
        mediaPickerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/media_picker").also {
            it.setMethodCallHandler(mediaPicker::handle)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/backup")
            .setMethodCallHandler(BackupBridge(appContext)::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/network")
            .setMethodCallHandler(NetworkBridge()::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/video_scan")
            .setMethodCallHandler(VideoScanBridge(appContext)::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/crop_export")
            .setMethodCallHandler(CropExportBridge(appContext)::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/wakelock")
            .setMethodCallHandler(wakeLockBridge::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/video_player")
            .setMethodCallHandler { call, result ->
                if (call.method != "openNativePlayer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uriStr = call.argument<String>("uri")
                if (uriStr == null) {
                    result.error("no_uri", "Video URI is required", null)
                    return@setMethodCallHandler
                }
                val title = call.argument<String>("title") ?: "Video"
                try {
                    val uri = android.net.Uri.parse(uriStr)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "video/*")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    val chooser = Intent.createChooser(intent, title).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(chooser)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("launch_failed", e.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/lens")
            .setMethodCallHandler { call, result ->
                if (call.method != "searchImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("no_path", "Image path is required", null)
                    return@setMethodCallHandler
                }
                val file = java.io.File(path)
                if (!file.exists()) {
                    result.error("not_found", "File not found", null)
                    return@setMethodCallHandler
                }
                try {
                    val uri: android.net.Uri = androidx.core.content.FileProvider.getUriForFile(
                        appContext,
                        "${appContext.packageName}.fileprovider",
                        file
                    )
                    val pm = appContext.packageManager

                    val lensIntent = Intent(Intent.ACTION_SEND).apply {
                        setPackage("com.google.ar.lens")
                        type = "image/*"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (lensIntent.resolveActivity(pm) != null) {
                        startActivity(lensIntent)
                        result.success("lens")
                        return@setMethodCallHandler
                    }

                    val gsaIntent = Intent(Intent.ACTION_SEND).apply {
                        setPackage("com.google.android.googlequicksearchbox")
                        type = "image/*"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (gsaIntent.resolveActivity(pm) != null) {
                        startActivity(gsaIntent)
                        result.success("google_app")
                        return@setMethodCallHandler
                    }

                    val chooser = Intent.createChooser(
                        Intent(Intent.ACTION_SEND).apply {
                            type = "image/*"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        },
                        "Search with Google Lens"
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(chooser)
                    result.success("chooser")
                } catch (e: Exception) {
                    result.error("lens_failed", e.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/studio_notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "completed") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= 33 && appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channelId = "antigravity_results"
                manager.createNotificationChannel(NotificationChannel(channelId,
                    call.argument<String>("channel") ?: "Private results", NotificationManager.IMPORTANCE_DEFAULT))
                val launch = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
                val intent = PendingIntent.getActivity(appContext, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val notification = Notification.Builder(appContext, channelId)
                    .setSmallIcon(android.R.drawable.ic_menu_gallery)
                    .setContentTitle(call.argument<String>("title"))
                    .setContentText(call.argument<String>("body"))
                    .setVisibility(Notification.VISIBILITY_PRIVATE)
                    .setAutoCancel(true)
                    .setContentIntent(intent)
                    .build()
                manager.notify((call.argument<String>("id") ?: "result").hashCode(), notification)
                result.success(true)
            }
    }

    override fun onDestroy() {
        security.cancelPending()
        securityChannel?.setMethodCallHandler(null)
        securityChannel = null
        mediaOrganizer.close()
        mediaOrganizerChannel?.setMethodCallHandler(null)
        mediaOrganizerChannel = null
        mediaPicker.close()
        mediaPickerChannel?.setMethodCallHandler(null)
        mediaPickerChannel = null
        wakeLockBridge.releaseAll()
        super.onDestroy()
    }

    @Deprecated("Android credential confirmation result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!mediaOrganizer.onActivityResult(requestCode, resultCode) &&
            !mediaPicker.onActivityResult(requestCode, resultCode, data) &&
            !security.onActivityResult(requestCode, resultCode)) super.onActivityResult(requestCode, resultCode, data)
    }
}
