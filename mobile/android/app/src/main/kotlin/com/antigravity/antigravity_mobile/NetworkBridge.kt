package com.antigravity.antigravity_mobile

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

/** Inspect local LAN/hotspot interfaces without scanning Wi-Fi or reading SSIDs. */
class NetworkBridge {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "interfaces") { result.notImplemented(); return }
        try {
            val rows = mutableListOf<Map<String, Any>>()
            for (network in Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!network.isUp || network.isLoopback) continue
                val name = network.name.lowercase()
                // Cellular/VPN addresses can also be 10.x. They are never LAN sources.
                if (!(name.startsWith("wlan") || name.startsWith("swlan") || name.startsWith("ap") ||
                    name.startsWith("eth") || name.startsWith("rndis") || name.startsWith("usb") ||
                    name.startsWith("ncm") || name.startsWith("softap") || name.startsWith("br") || name.startsWith("bt-pan"))) continue
                for (local in network.interfaceAddresses) {
                    val address = local.address
                    if (address !is Inet4Address || address.isLoopbackAddress) continue
                    rows.add(mapOf("name" to network.name, "address" to address.hostAddress!!,
                        "prefix" to local.networkPrefixLength.toInt()))
                }
            }
            result.success(rows)
        } catch (error: Exception) {
            result.error("network_inspection", "Could not inspect local network interfaces.", null)
        }
    }
}
