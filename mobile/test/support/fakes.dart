import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/platform/platform_services.dart';
import 'package:antigravity_mobile/data/secrets/secret_store.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:antigravity_mobile/features/reface/reface_video_trimmer.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'fake_video_controller.dart';

/// A valid 1x1 PNG, so Image.memory has something decodable in widget tests.
final tinyPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xFF,
  0xFF,
  0x3F,
  0x00,
  0x05,
  0xFE,
  0x02,
  0xFE,
  0xDC,
  0xCC,
  0x59,
  0xE7,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

const testSession = ServerSession(
  serverId: 'srv_7f3a91c2',
  name: 'RTX-PC',
  host: '192.168.1.20',
  port: 8443,
  fingerprint:
      'ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34',
  token: 'agm_0123456789abcdef0123456789abcdef01234567',
);

class FakeMobileApi implements MobileApi {
  Capabilities capabilities_ = Capabilities.fromJson(
    fixture('Capabilities.idle'),
  );
  ApiException? capabilitiesError;
  ApiException? analyzeError;
  AnalyzeImageResponse analyzeResult = AnalyzeImageResponse.fromJson(
    fixture('AnalyzeImageResponse.two_faces_one_body'),
  );
  final analyzeCalls = <Uint8List>[];
  final analyzeOptions = <AnalyzeOptions>[];

  /// Scripted answers (e.g. one response per photo). Null = [analyzeResult] every time.
  Future<AnalyzeImageResponse> Function(Uint8List jpeg, AnalyzeOptions options)?
  analyzeHandler;

  final groupingCalls = <GroupingPlanRequest>[];
  ApiException? groupingError;
  GroupingPlanResponse Function(GroupingPlanRequest request)? groupingHandler;

  @override
  Future<Capabilities> capabilities() async {
    if (capabilitiesError != null) throw capabilitiesError!;
    return capabilities_;
  }

  @override
  Future<Health> health() async => Health.fromJson(fixture('Health.ok'));

  @override
  Future<AnalyzeImageResponse> analyzeImage(
    Uint8List jpegBytes, {
    String filename = 'photo.jpg',
    AnalyzeOptions options = const AnalyzeOptions(),
  }) async {
    analyzeCalls.add(jpegBytes);
    analyzeOptions.add(options);
    if (analyzeError != null) throw analyzeError!;
    final handler = analyzeHandler;
    if (handler != null) return handler(jpegBytes, options);
    return analyzeResult;
  }

  @override
  Future<GroupingPlanResponse> groupingPlan(GroupingPlanRequest request) async {
    groupingCalls.add(request);
    if (groupingError != null) throw groupingError!;
    final handler = groupingHandler;
    return handler != null
        ? handler(request)
        : GroupingPlanResponse(mode: request.mode);
  }
}

/// The phone's photo library, made of byte arrays.
class FakeMediaLibrary implements MediaLibrary {
  FakeMediaLibrary({
    List<AlbumInfo>? albums,
    Map<String, List<AssetInfo>>? assets,
  }) : _albums = albums ?? [],
       _assets = assets ?? {};

  final List<AlbumInfo> _albums;
  final Map<String, List<AssetInfo>> _assets;
  final Map<String, Uint8List> bytes = {};
  final Set<String> unreadable = {};
  var access = true;
  final reads = <String>[];
  final maxSides = <int>[];
  var cacheClears = 0;

  void addAlbum(AlbumInfo album, List<AssetInfo> assets) {
    _albums.add(album);
    _assets[album.id] = assets;
  }

  /// Photos appear in / disappear from an album (the user took pictures).
  void setAlbum(String id, List<AssetInfo> assets) => _assets[id] = assets;

  @override
  Future<bool> requestAccess() async => access;

  @override
  Future<List<AlbumInfo>> albums() async => _albums;

  @override
  Stream<List<AssetInfo>> photos(
    Set<String> albumIds, {
    int pageSize = 400,
  }) async* {
    for (final id in albumIds) {
      final list = _assets[id] ?? const <AssetInfo>[];
      for (var i = 0; i < list.length; i += pageSize) {
        yield list.sublist(i, math.min(list.length, i + pageSize));
      }
    }
  }

  @override
  Future<Uint8List?> downscaledJpeg(
    String assetId, {
    required int width,
    required int height,
    required int maxSide,
  }) async {
    reads.add(assetId);
    maxSides.add(maxSide);
    if (unreadable.contains(assetId)) return null;
    return bytes[assetId] ?? Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
  }

  @override
  Future<Uint8List?> thumbnail(
    String assetId, {
    required int width,
    required int height,
    int size = 256,
  }) async => bytes[assetId];

  @override
  Future<Uint8List?> viewerImage(String assetId, {int maxSide = 1800}) async =>
      bytes[assetId];

  @override
  Future<void> clearCache() async => cacheClears++;
}

List<AssetInfo> syntheticAssets(
  int count, {
  int idStart = 1,
  int modifiedAt = 1000,
}) => [
  for (var i = 0; i < count; i++)
    AssetInfo(
      id: 'asset-${idStart + i}',
      width: 1200,
      height: 800,
      modifiedAt: modifiedAt,
      takenAt: modifiedAt + i,
    ),
];

/// Records what the scan asked of the Android foreground service.
class RecordingKeepAlive implements ScanKeepAlive {
  final events = <String>[];

  @override
  Future<void> start({required String title, required String text}) async =>
      events.add('start');

  @override
  Future<void> update(String text) async => events.add('update');

  @override
  Future<void> stop() async => events.add('stop');
}

class FakePairingApi implements PairingApi {
  String fingerprint =
      'ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34ab12cd34';
  ApiException? probeError;
  ApiException? completeError;
  final probeCalls = <(String, int)>[];
  final completeCalls = <Map<String, Object?>>[];

  @override
  Future<String> probeFingerprint(String host, int port) async {
    probeCalls.add((host, port));
    if (probeError != null) throw probeError!;
    return fingerprint;
  }

  @override
  Future<PairResponse> completePairing({
    required String host,
    required int port,
    required String fingerprint,
    required String code,
    required String deviceName,
  }) async {
    completeCalls.add({
      'host': host,
      'port': port,
      'fingerprint': fingerprint,
      'code': code,
      'deviceName': deviceName,
    });
    if (completeError != null) throw completeError!;
    return PairResponse.fromJson(fixture('PairResponse.ok'));
  }
}

class FakePermissions implements PermissionsService {
  FakePermissions([Map<AppPermission, PermissionState>? initial])
    : states =
          initial ??
          {for (final p in AppPermission.values) p: PermissionState.denied};

  final Map<AppPermission, PermissionState> states;
  final requested = <AppPermission>[];
  var settingsOpened = 0;
  PermissionState onRequest = PermissionState.granted;

  @override
  Future<Map<AppPermission, PermissionState>> status() async => Map.of(states);

  @override
  Future<PermissionState> request(AppPermission permission) async {
    requested.add(permission);
    states[permission] = onRequest;
    return onRequest;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

class FakePhotoPicker implements PhotoPicker {
  Uint8List? photo;
  var picks = 0;

  @override
  Future<Uint8List?> pickPhoto({int maxSide = 2560}) async {
    picks++;
    return photo;
  }
}

/// Everything a widget test needs: an in-memory database and fakes for every platform seam.
class TestEnv {
  TestEnv({this.session, FakeMobileApi? api})
    : api = api ?? FakeMobileApi(),
      db = AppDatabase(NativeDatabase.memory()),
      secrets = MemorySecretStore(),
      pairing = FakePairingApi(),
      permissions = FakePermissions(),
      picker = FakePhotoPicker(),
      tmp = Directory.systemTemp.createTempSync('ag_env_'),
      library = FakeMediaLibrary(),
      index = InMemoryEmbeddingIndex() {
    files = FileStore(Directory('${tmp.path}/crops'));
  }

  final ServerSession? session;
  final FakeMobileApi api;
  final AppDatabase db;
  final MemorySecretStore secrets;
  final FakePairingApi pairing;
  final FakePermissions permissions;
  final FakePhotoPicker picker;
  final Directory tmp;
  final FakeMediaLibrary library;
  final InMemoryEmbeddingIndex index;
  late final FileStore files;
  Future<RefaceTarget?> Function()? targetPicker;
  RefaceMediaSource? lastTargetSource;

  List<Override> get overrides => [
    databaseProvider.overrideWithValue(db),
    secretStoreProvider.overrideWithValue(secrets),
    initialSessionProvider.overrideWithValue(session),
    pairingApiProvider.overrideWithValue(pairing),
    mobileApiProvider.overrideWith(
      (ref) => ref.watch(sessionProvider) == null ? null : api,
    ),
    permissionsServiceProvider.overrideWithValue(permissions),
    photoPickerProvider.overrideWithValue(picker),
    refaceTargetPickerProvider.overrideWithValue((source) async {
      lastTargetSource = source;
      if (targetPicker != null) return targetPicker!();
      final photo = await picker.pickPhoto();
      return photo == null ? null : RefaceTarget.photo(photo);
    }),
    refaceVideoControllerProvider.overrideWithValue(
      (file) => FakeTrimVideoController(file),
    ),
    deviceNameProvider.overrideWith((ref) async => 'Test phone'),
    fileStoreProvider.overrideWithValue(files),
    mediaLibraryProvider.overrideWithValue(library),
    embeddingIndexProvider.overrideWithValue(index),
    scanKeepAliveProvider.overrideWithValue(const NoKeepAlive()),
    autoResumeScanProvider.overrideWithValue(false),
  ];

  Future<SettingsSnapshot> settingsSnapshot() => AppSettings(db).load();

  Future<void> pump(
    WidgetTester tester, {
    List<Override> extra = const [],
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(overrides: [...overrides, ...extra], child: const App()),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    // unmount first so the polling provider cancels its timer, then close the database
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}
