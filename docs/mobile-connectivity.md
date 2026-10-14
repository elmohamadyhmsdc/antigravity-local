# Mobile connectivity

The phone can use a router, its own hotspot, the PC's hotspot, or USB forwarding. The mobile API is a local HTTPS server; Internet access is not a prerequisite. No packages, models or public relay services are needed.

## Reconnect after an address change

- Open the PC dashboard → **Mobile Devices**. Its adapter addresses and pairing QR refresh after network changes without replacing the certificate or paired devices.
- In the phone app open **Connection help** from Settings, the offline banner, or Welcome. **Find my PC on this network** discovers local candidates. A paired phone verifies its saved certificate and server ID before using its token, then saves only the new endpoint.
- If discovery is blocked, type the current PC address and port and select **Verify and save PC address**. Do not forget the PC merely because DHCP changed its address.
- Existing scan/Studio clients keep the same identity and use the new endpoint. Offline-paused scans can resume; user pauses and backup/storage maintenance prevent automatic resume.

## Which address to choose

| Network | PC address |
|---|---|
| Phone hotspot | The laptop's Wi-Fi address, not the phone/gateway address |
| PC hotspot | The PC hotspot adapter's address, which can differ from Ethernet/router Wi-Fi |
| Router | A PC interface reachable from the phone's local network |
| USB forwarding | `127.0.0.1`, after `adb reverse tcp:8443 tcp:8443` (substitute the configured API port) |

Windows hotspot/USB interfaces are included even if they do not register in hostname DNS. Android LAN sockets select the source address of the matching Wi-Fi/hotspot/USB subnet; cellular and VPN interfaces are excluded from that source selection. Pooled connections are refreshed on local interface changes and app resume. Certificate pinning remains mandatory and HTTP redirects are disabled.

## Ports and restrictions

HTTPS uses TCP **8443**, discovery uses UDP **8445**, and PC administration stays on loopback TCP **8444** by default. UDP discovery carries a random request nonce and server identity/address hints, never a certificate pin, token, photo or user library record. Announcements are untrusted until pinned HTTPS verifies the PC.

Windows Firewall must allow the existing Python interpreter on the active profile. The optional, reviewed `the app/allow_mobile_lan.ps1` script creates only named TCP/UDP rules for that interpreter and `LocalSubnet` on Private/Public profiles. It requires an administrator and is never run automatically. Pass `-PythonPath` if executing a downloaded copy outside the app directory. The dashboard shows the exact command for this installation.

Guest/client isolation, VPN policies and vendor hotspot settings can block local traffic. The app cannot override those policies; the help screen explains the local-network setting or USB alternative. A phone may turn an idle hotspot off automatically. A loopback-bound server offers USB/emulator addresses, rather than an unreachable LAN QR.

## Verification on 2026-10-14

The live phone hotspot changed the PC address from `10.166.93.149` to `10.183.49.149` while the old server QR remained stale. TCP connectivity to the current address succeeded from the Android application UID. After deploying the server changes, pinned/local-certificate HTTPS health and UDP discovery from the same application UID succeeded, with the original PC certificate and paired phone preserved.

Automated checks cover changed addresses/QR/mDNS, a hotspot adapter missing from DNS, loopback-only binding, UDP correlation/malformed packets/secret omission, subnet routing, wrong PC identities and certificate rejection before credentials, endpoint persistence, retained clients during a move, disposed status checks, scan recovery, explicit pauses and maintenance. The APK is built offline. The new native interface bridge is compiled; installation and full phone/router/PC-hotspot/VPN GUI acceptance are not claimed by command-line probes.

Final verification: **361 Flutter tests passed**, the Dart library analyzer reported no issues, and the Android debug APK built offline after the final source changes. Five server connectivity tests, 11 dashboard tests, all 28 API contract tests and five statelessness tests passed. Old hostname DNS addresses are filtered against currently assigned, active adapters. The optional firewall script was parsed without executing it or changing Windows rules.
