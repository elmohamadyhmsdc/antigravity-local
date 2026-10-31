package com.antigravity.antigravity_mobile

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Manages native Android PARTIAL_WAKE_LOCK and high-performance WifiLock
 * during background operations (e.g. library photo/video scanning, Studio jobs).
 *
 * This prevents Android OS and vendor power managers (Samsung One UI) from
 * suspending the CPU or putting the Wi-Fi radio to sleep while the screen is locked.
 */
class WakeLockBridge(private val context: Context) {
    private val powerManager by lazy {
        context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    }
    private val wifiManager by lazy {
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var lockCount = 0

    @Synchronized
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                try {
                    lockCount++
                    if (lockCount == 1) {
                        if (wakeLock == null) {
                            wakeLock = powerManager?.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK,
                                "antigravity:scan_wakelock"
                            )?.apply {
                                setReferenceCounted(false)
                            }
                        }
                        wakeLock?.let {
                            if (!it.isHeld) {
                                it.acquire(12 * 60 * 60 * 1000L) // 12-hour safety ceiling
                            }
                        }

                        if (wifiLock == null) {
                            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                            } else {
                                @Suppress("DEPRECATION")
                                WifiManager.WIFI_MODE_FULL_HIGH_PERF
                            }
                            wifiLock = wifiManager?.createWifiLock(mode, "antigravity:scan_wifilock")?.apply {
                                setReferenceCounted(false)
                            }
                        }
                        wifiLock?.let {
                            if (!it.isHeld) {
                                it.acquire()
                            }
                        }
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("wakelock_error", e.message, null)
                }
            }
            "release" -> {
                try {
                    if (lockCount > 0) {
                        lockCount--
                    }
                    if (lockCount == 0) {
                        wakeLock?.let {
                            if (it.isHeld) it.release()
                        }
                        wifiLock?.let {
                            if (it.isHeld) it.release()
                        }
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("wakelock_error", e.message, null)
                }
            }
            "status" -> {
                result.success(
                    mapOf(
                        "wakeLockHeld" to (wakeLock?.isHeld == true),
                        "wifiLockHeld" to (wifiLock?.isHeld == true),
                        "lockCount" to lockCount
                    )
                )
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    fun releaseAll() {
        lockCount = 0
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {}
    }
}
