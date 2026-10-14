import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lan_host.dart';

class LanInterface {
  const LanInterface(this.name, this.address, this.prefix);
  final String name, address;
  final int prefix;
  static int? _v4(String host) {
    final ip = InternetAddress.tryParse(host);
    if (ip == null || ip.type != InternetAddressType.IPv4) return null;
    return ip.rawAddress.fold<int>(0, (value, byte) => (value << 8) | byte);
  }

  bool contains(String host) {
    final local = _v4(address), remote = _v4(host);
    if (local == null || remote == null || prefix < 1 || prefix > 32) {
      return false;
    }
    return local >> (32 - prefix) == remote >> (32 - prefix);
  }

  String? get broadcast {
    final value = _v4(address);
    if (value == null || prefix < 1 || prefix > 30) return null;
    final broadcast = value | ((1 << (32 - prefix)) - 1);
    return [24, 16, 8, 0].map((shift) => (broadcast >> shift) & 255).join('.');
  }
}

class LanEndpoint {
  const LanEndpoint(this.host, this.port, {this.serverId, this.name});
  final String host;
  final int port;
  final String? serverId, name;
  String get label => '$host:$port';
}

abstract interface class LanNetwork {
  bool get supported;
  Future<List<LanInterface>> interfaces();
  Future<List<LanEndpoint>> discover({String? serverId});
}

class SystemLanNetwork implements LanNetwork {
  static const _channel = MethodChannel('antigravity/network');
  @override
  bool get supported => Platform.isAndroid;
  @override
  Future<List<LanInterface>> interfaces() async {
    if (!supported) return const [];
    final rows =
        await _channel.invokeListMethod<dynamic>('interfaces') ?? const [];
    return [
      for (final row in rows)
        if (row is Map &&
            row['name'] is String &&
            row['address'] is String &&
            row['prefix'] is int)
          LanInterface(
            row['name'] as String,
            row['address'] as String,
            row['prefix'] as int,
          ),
    ];
  }

  @override
  Future<List<LanEndpoint>> discover({String? serverId}) async =>
      discoverLan(await interfaces(), serverId: serverId);
}

String? lanSourceAddress(String host, List<LanInterface> interfaces) {
  final matches = interfaces.where((i) => i.contains(host)).toList()
    ..sort((a, b) => b.prefix.compareTo(a.prefix));
  return matches.firstOrNull?.address;
}

/// Binding to the hotspot's local interface avoids sending LAN sockets down the
/// phone's cellular default route. TLS identity checks still happen afterwards.
Future<ConnectionTask<Socket>> startLanConnection(String host, int port) async {
  String? source;
  if (Platform.isAndroid &&
      InternetAddress.tryParse(host)?.isLoopback != true) {
    try {
      source = lanSourceAddress(host, await SystemLanNetwork().interfaces());
    } on Object {
      /* Normal OS routing remains available if interface inspection fails. */
    }
  }
  return Socket.startConnect(host, port, sourceAddress: source);
}

/// UDP only locates candidates. Every candidate must pass the saved TLS pin and
/// server-id check before a saved token or any user media is sent.
Future<List<LanEndpoint>> discoverLan(
  List<LanInterface> interfaces, {
  String? serverId,
  int port = 8445,
  Duration duration = const Duration(milliseconds: 1600),
  List<String>? targets,
}) async {
  final random = Random.secure();
  final nonce = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final request = utf8.encode(
    jsonEncode({'service': 'antigravity-mobile', 'version': 1, 'nonce': nonce}),
  );
  final results = <String, LanEndpoint>{};
  final bindings = interfaces.isEmpty
      ? <LanInterface?>[null]
      : interfaces.take(4).toList();
  await Future.wait(
    bindings.map((interface) async {
      RawDatagramSocket? socket;
      StreamSubscription<RawSocketEvent>? events;
      try {
        socket = await RawDatagramSocket.bind(
          interface?.address ?? InternetAddress.anyIPv4,
          0,
        );
        socket.broadcastEnabled = true;
        final active = socket;
        events = socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? packet;
          while ((packet = active.receive()) != null) {
            final data = packet!;
            if (data.data.length > 2048 ||
                !isLanHost(data.address.address) ||
                results.length >= 16) {
              continue;
            }
            try {
              final value = jsonDecode(utf8.decode(data.data));
              if (value is! Map ||
                  value['service'] != 'antigravity-mobile' ||
                  value['version'] != 1 ||
                  value['nonce'] != nonce ||
                  value['port'] is! int ||
                  value['port'] < 1 ||
                  value['port'] > 65535 ||
                  value['server_id'] is! String ||
                  (serverId != null && value['server_id'] != serverId)) {
                continue;
              }
              final endpoint = LanEndpoint(
                data.address.address,
                value['port'] as int,
                serverId: value['server_id'] as String,
                name: value['name'] is String ? value['name'] as String : null,
              );
              results[endpoint.label] = endpoint;
            } on Object {
              /* Ignore unrelated or malformed LAN packets. */
            }
          }
        });
        for (final host
            in targets ??
                {
                  interface?.broadcast,
                  '255.255.255.255',
                }.whereType<String>().toList()) {
          try {
            socket.send(request, InternetAddress(host), port);
          } on SocketException {
            /* Try the other interfaces. */
          }
        }
        await Future<void>.delayed(duration);
      } on SocketException {
        /* A removed interface must not fail other routes. */
      } finally {
        await events?.cancel();
        socket?.close();
      }
    }),
  );
  return results.values.toList();
}

final lanNetworkProvider = Provider<LanNetwork>((ref) => SystemLanNetwork());
