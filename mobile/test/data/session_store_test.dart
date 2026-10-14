import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/session_store.dart';
import 'package:antigravity_mobile/data/secrets/secret_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = ServerSession(
  serverId: 'srv_7f3a91c2',
  name: 'RTX-PC',
  host: '192.168.1.20',
  port: 8443,
  fingerprint:
      'ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34',
  token: 'agm_secret_token',
);

void main() {
  late AppDatabase db;
  late MemorySecretStore secrets;
  late SessionStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secrets = MemorySecretStore();
    store = SessionStore(
      db,
      secrets,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );
  });
  tearDown(() => db.close());

  test('nothing is paired on a fresh install', () async {
    expect(await store.load(), isNull);
  });

  test('save then load restores the whole session', () async {
    await store.save(_session);
    final loaded = (await store.load())!;
    expect(
      (loaded.serverId, loaded.name, loaded.host, loaded.port),
      ('srv_7f3a91c2', 'RTX-PC', '192.168.1.20', 8443),
    );
    expect(loaded.fingerprint, _session.fingerprint);
    expect(loaded.token, 'agm_secret_token');
  });

  test(
    'the bearer token goes to the keystore, never into the database',
    () async {
      await store.save(_session);
      expect(secrets.values.values, contains('agm_secret_token'));
      final rows = await db.customSelect('SELECT * FROM servers').get();
      expect(
        rows.single.data.values.map((v) => '$v'),
        isNot(contains('agm_secret_token')),
      );
    },
  );

  test(
    'a lost keystore entry means "not paired" instead of a half-working session',
    () async {
      await store.save(_session);
      secrets.values.clear();
      expect(await store.load(), isNull);
    },
  );

  test(
    'clear forgets the PC and its token but keeps everything else',
    () async {
      await db.putSetting('strictness', 'balanced');
      await store.save(_session);
      await store.clear(_session.serverId);
      expect(await store.load(), isNull);
      expect(secrets.values, isEmpty);
      expect(await db.setting('strictness'), 'balanced');
    },
  );

  test('re-pairing the same PC replaces its row', () async {
    await store.save(_session);
    await store.save(_session.copyWith(host: '192.168.1.99'));
    expect((await store.load())!.host, '192.168.1.99');
    expect(
      await db
          .customSelect('SELECT COUNT(*) AS n FROM servers')
          .map((r) => r.read<int>('n'))
          .getSingle(),
      1,
    );
  });

  test(
    'moving the endpoint preserves pairing time and keystore token; it cannot resurrect a forgotten PC',
    () async {
      await store.save(_session);
      final before = await db.latestServer();
      await store.move(_session.copyWith(host: '10.183.49.149', port: 9443));
      final after = await db.latestServer();
      expect(after!.pairedAt, before!.pairedAt);
      expect((await store.load())!.token, _session.token);
      expect((await store.load())!.host, '10.183.49.149');
      await store.clear(_session.serverId);
      await store.move(_session);
      expect(await store.load(), isNull);
    },
  );
}
