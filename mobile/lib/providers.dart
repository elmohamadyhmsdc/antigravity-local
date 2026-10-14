import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'data/api/api_exception.dart';
import 'data/api/dtos/system.dart';
import 'data/api/mobile_api.dart';
import 'data/db/app_database.dart';
import 'data/platform/platform_services.dart';
import 'data/repositories/session_store.dart';
import 'data/secrets/secret_store.dart';
import 'data/platform/lan_network.dart';
import 'data/api/connection_recovery.dart';

// ---- storage ----------------------------------------------------------------------

/// The opened (encrypted) database. Overridden in main.dart and in tests.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final secretStoreProvider = Provider<SecretStore>(
  (ref) => const FlutterSecretStore(FlutterSecureStorage()),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) =>
      SessionStore(ref.watch(databaseProvider), ref.watch(secretStoreProvider)),
);

// ---- session (which PC we are paired with) ------------------------------------------

/// The session loaded at start-up (main.dart overrides this).
final initialSessionProvider = Provider<ServerSession?>((ref) => null);

class SessionNotifier extends Notifier<ServerSession?> {
  @override
  ServerSession? build() => ref.read(initialSessionProvider);

  Future<void> pair(ServerSession session) async {
    await ref.read(sessionStoreProvider).save(session);
    state = session;
  }

  Future<bool> relocate(ServerSession expected, ServerSession verified) async {
    if (!identical(state, expected) ||
        expected.serverId != verified.serverId ||
        expected.token != verified.token ||
        expected.fingerprint != verified.fingerprint) {
      return false;
    }
    await ref.read(sessionStoreProvider).move(verified);
    if (!identical(state, expected)) return false;
    state = verified;
    return true;
  }

  /// Forget the PC. Library data on the phone is untouched.
  Future<void> forget() async {
    final current = state;
    if (current != null) {
      await ref.read(sessionStoreProvider).clear(current.serverId);
    }
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, ServerSession?>(
  SessionNotifier.new,
);

// ---- network ------------------------------------------------------------------------

final pairingApiProvider = Provider<PairingApi>(
  (ref) => const HttpPairingApi(),
);

final endpointVerifierProvider =
    Provider<Future<VerifiedEndpoint> Function(ServerSession, LanEndpoint)>(
      (ref) =>
          (session, endpoint) => verifyEndpoint(session, endpoint),
    );

/// The authenticated, certificate-pinned client for the paired PC (null when not paired).
final mobileApiProvider = Provider<MobileApi?>((ref) {
  final identity = ref.watch(
    sessionProvider.select(
      (s) => s == null ? null : (s.serverId, s.fingerprint, s.token),
    ),
  );
  if (identity == null) return null;
  final client = HttpMobileApi(ref.read(sessionProvider)!);
  ref.listen(sessionProvider, (_, next) {
    if (next != null &&
        (next.serverId, next.fingerprint, next.token) == identity) {
      client.relocate(next);
    }
  });
  ref.onDispose(client.close);
  return client;
});

final lanSignatureProvider = StreamProvider.autoDispose<String>((ref) {
  final network = ref.watch(lanNetworkProvider);
  if (!network.supported) return Stream.value('');
  final events = StreamController<String>();
  var closed = false;
  Timer? timer;
  Future<void> poll() async {
    try {
      final interfaces = await network.interfaces();
      if (!closed) {
        events.add(
          (interfaces.map((i) => '${i.name}:${i.address}/${i.prefix}').toList()
                ..sort())
              .join(','),
        );
      }
    } on Object {
      /* Retain the last known signature. */
    }
    if (!closed) timer = Timer(const Duration(seconds: 5), poll);
  }

  poll();
  ref.onDispose(() {
    closed = true;
    timer?.cancel();
    events.close();
  });
  return events.stream.distinct();
});

// ---- OS services ----------------------------------------------------------------------

final permissionsServiceProvider = Provider<PermissionsService>(
  (ref) => const OsPermissionsService(),
);
final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => GalleryPhotoPicker(),
);
final deviceNameProvider = FutureProvider<String>((ref) => readDeviceName());

// ---- server status (Home chip) --------------------------------------------------------

sealed class ServerStatus {
  const ServerStatus();
}

class ServerChecking extends ServerStatus {
  const ServerChecking();
}

class ServerReady extends ServerStatus {
  const ServerReady(this.capabilities);
  final Capabilities capabilities;
}

class ServerBusy extends ServerStatus {
  const ServerBusy(this.capabilities);
  final Capabilities capabilities;
  BusyInfo get busy => capabilities.busy!;
}

class ServerOffline extends ServerStatus {
  const ServerOffline(this.error);
  final ApiException error;
}

/// The PC no longer accepts our token (it was revoked on the PC).
class ServerRevoked extends ServerStatus {
  const ServerRevoked();
}

const statusPollInterval = Duration(seconds: 15);

Future<ServerStatus> checkServer(MobileApi api) async {
  try {
    final caps = await api.capabilities();
    return caps.isBusy ? ServerBusy(caps) : ServerReady(caps);
  } on ApiException catch (e) {
    return e.isUnauthorized ? const ServerRevoked() : ServerOffline(e);
  }
}

/// Polls the PC while something watches it. Invalidate to check right now.
final serverStatusProvider = StreamProvider.autoDispose<ServerStatus>((ref) {
  final api = ref.watch(mobileApiProvider);
  final controller = StreamController<ServerStatus>();
  Timer? timer;
  var closed = false;

  Future<void> poll() async {
    if (api == null || closed) return;
    var status = await checkServer(api);
    if (closed) return;
    final saved = ref.read(sessionProvider);
    final network = ref.read(lanNetworkProvider);
    if (!closed &&
        status is ServerOffline &&
        saved != null &&
        network.supported) {
      controller.add(status);
      try {
        final recovered = await recoverEndpoint(saved, network);
        if (!closed &&
            recovered != null &&
            await ref
                .read(sessionProvider.notifier)
                .relocate(saved, recovered.session)) {
          status = recovered.capabilities.isBusy
              ? ServerBusy(recovered.capabilities)
              : ServerReady(recovered.capabilities);
        }
      } on ApiException catch (error) {
        if (error.isUnauthorized) status = const ServerRevoked();
      } on Object {
        /* Keep the original connection error. */
      }
    }
    if (closed) return;
    controller.add(status);
    timer = Timer(statusPollInterval, poll);
  }

  controller.add(const ServerChecking());
  poll();
  ref.onDispose(() {
    closed = true;
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

// ---- library stats (Home tiles) ----------------------------------------------------------

final libraryStatsProvider = StreamProvider.autoDispose<LibraryStats>(
  (ref) => ref.watch(databaseProvider).watchLibraryStats(),
);
