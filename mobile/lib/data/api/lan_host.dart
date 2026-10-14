/// The PC is reached over the home Wi-Fi only. Pairing refuses anything that is not a
/// private-network address, so a link or a typo can never point the phone (and its photos)
/// at a server on the internet.
bool isLanHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  if (h == 'localhost') return true;

  final v4 = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  ).firstMatch(h);
  if (v4 != null) {
    final o = [for (var i = 1; i <= 4; i++) int.parse(v4.group(i)!)];
    if (o.any((n) => n > 255)) return false;
    return o[0] ==
            10 || //                            10.0.0.0/8      (also the Android emulator's 10.0.2.2)
        (o[0] == 172 && o[1] >= 16 && o[1] <= 31) || //  172.16.0.0/12
        (o[0] == 192 && o[1] == 168) || //                192.168.0.0/16
        (o[0] == 169 && o[1] == 254) || //                link-local
        o[0] == 127; //                                   loopback
  }

  if (h.contains(':')) {
    // IPv6 literal: loopback, link-local (fe80::/10) or unique-local (fc00::/7)
    return h == '::1' ||
        h.startsWith('fe8') ||
        h.startsWith('fe9') ||
        h.startsWith('fea') ||
        h.startsWith('feb') ||
        h.startsWith('fc') ||
        h.startsWith('fd');
  }

  // names: mDNS (`my-pc.local`) or a bare single-label host name; never a dotted internet name
  return h.endsWith('.local') || !h.contains('.');
}
