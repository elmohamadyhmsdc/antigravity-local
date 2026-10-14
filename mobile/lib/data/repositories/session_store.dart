import '../api/mobile_api.dart';
import '../db/app_database.dart';
import '../secrets/secret_store.dart';

/// Persists which PC this phone is paired with: the non-secret half (address, pinned
/// fingerprint) in the encrypted database, the bearer token in the Android Keystore.
class SessionStore {
  SessionStore(this._db, this._secrets, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final SecretStore _secrets;
  final DateTime Function() _clock;

  static String _tokenKey(String serverId) => 'token.$serverId';

  Future<ServerSession?> load() async {
    final row = await _db.latestServer();
    if (row == null) return null;
    final token = await _secrets.read(_tokenKey(row.id));
    if (token == null) {
      return null; // keystore entry lost (e.g. app data restored): pair again
    }
    return ServerSession(
      serverId: row.id,
      name: row.name,
      host: row.host,
      port: row.port,
      fingerprint: row.fingerprint,
      token: token,
    );
  }

  Future<void> save(ServerSession session) async {
    await _secrets.write(_tokenKey(session.serverId), session.token);
    await _db.upsertServer(
      ServersCompanion.insert(
        id: session.serverId,
        name: session.name,
        host: session.host,
        port: session.port,
        fingerprint: session.fingerprint,
        pairedAt: _clock().millisecondsSinceEpoch,
      ),
    );
  }

  /// Forget one PC: its token leaves the keystore and its row leaves the database.
  Future<void> clear(String serverId) async {
    await _secrets.delete(_tokenKey(serverId));
    await _db.deleteServer(serverId);
  }

  Future<void> touch(String serverId) =>
      _db.touchServer(serverId, _clock().millisecondsSinceEpoch);

  Future<void> move(ServerSession session) =>
      _db.moveServer(session.serverId, session.host, session.port);
}
