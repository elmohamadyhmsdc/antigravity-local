import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/data/repositories/video_scan_coverage.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late VideoScanCoverage coverage;
  setUp(() { db = AppDatabase(NativeDatabase.memory()); coverage = VideoScanCoverage(db); });
  tearDown(() => db.close());

  Future<MediaRow> video(String asset, {String status = 'done'}) async {
    final id = await seedMedia(db, asset: asset, kind: 'video', status: status);
    return (await LibraryRepository(db).mediaById(id))!;
  }

  test('quick is the default, the preference and coverage travel in backups', () async {
    expect((await AppSettings(db).load()).videoScanMode, VideoScanMode.quick);
    await AppSettings(db).setVideoScanMode(VideoScanMode.detailed);
    expect((await AppSettings(db).load()).videoScanMode, VideoScanMode.detailed);
    expect(SettingKeys.isBackedUp(SettingKeys.videoScanMode), isTrue);
    expect(SettingKeys.isBackedUp('${VideoScanCoverage.prefix}8'), isTrue);
    expect(SettingKeys.isBackedUp('${VideoScanCoverage.detailPrefix}8'), isTrue);
    expect(SettingKeys.isBackedUp('video.job.8'), isFalse);
  });

  test('upgrade preserves completed photos, observations and unrelated video cursors', () async {
    final photo = await seedMedia(db, asset: 'photo');
    final chosen = await video('chosen');
    final other = await video('other', status: 'pending');
    final face = await seedFace(db, mediaId: chosen.id);
    await coverage.complete(chosen, VideoScanMode.quick, clean: true);
    await (db.update(db.media)..where((m) => m.id.equals(other.id))).write(
      const MediaCompanion(lastScannedFrame: Value(901)));
    await db.putSetting('video.local.${chosen.id}', 'old grid');
    expect(await coverage.requestDetailed(chosen.id), isTrue);
    final repo = LibraryRepository(db);
    expect((await repo.mediaById(photo))!.scanStatus, 'done');
    expect((await repo.mediaById(other.id))!.lastScannedFrame, 901);
    expect((await repo.mediaById(chosen.id))!.lastScannedFrame, 0);
    expect((await repo.nextPending())!.id, chosen.id);
    expect((await db.select(db.faces).get()).single.id, face);
    expect(await db.setting('video.local.${chosen.id}'), isNull);
    expect(await coverage.requestedMode(chosen, VideoScanMode.quick), VideoScanMode.detailed);
    final item = (await MediaQueries(db).page(const MediaFilter(kind: 'video'), offset: 0, limit: 10))
        .singleWhere((m) => m.id == chosen.id);
    expect(item.videoScanMode, VideoScanMode.quick);
  });

  test('request during quick scanning waits for commit before resetting the grid', () async {
    final m = await video('inflight', status: 'scanning');
    await db.putSetting('video.local.${m.id}', 'pinned');
    await (db.update(db.media)..where((row) => row.id.equals(m.id))).write(
      const MediaCompanion(lastScannedFrame: Value(240)));
    expect(await coverage.requestDetailed(m.id), isTrue);
    expect(await db.setting('video.local.${m.id}'), 'pinned');
    expect((await LibraryRepository(db).mediaById(m.id))!.lastScannedFrame, 240);
    await coverage.complete(m, VideoScanMode.quick, clean: true);
    expect((await LibraryRepository(db).mediaById(m.id))!.scanStatus, 'pending');
    expect((await LibraryRepository(db).mediaById(m.id))!.lastScannedFrame, 0);
    await coverage.complete(m, VideoScanMode.detailed, clean: true);
    expect(await coverage.detailRequested(m), isFalse);
    expect(await coverage.mode(m), VideoScanMode.detailed);
  });

  test('unchanged completed legacy files are not queued by the quick preference', () async {
    final m = await video('legacy');
    expect(await coverage.requestDetailed(m.id), isFalse);
    expect((await LibraryRepository(db).mediaById(m.id))!.scanStatus, 'done');
    expect(await LibraryRepository(db).nextPending(), isNull);
    await coverage.complete(m, VideoScanMode.detailed, clean: true);
    await coverage.complete(m, VideoScanMode.quick, clean: true);
    expect(await coverage.mode(m), VideoScanMode.detailed);
  });

  test('warnings and changed sources cannot receive a false completed coverage label', () async {
    final m = await video('warning');
    await coverage.complete(m, VideoScanMode.quick, clean: false);
    expect(await coverage.mode(m), isNull);
    await coverage.complete(m, VideoScanMode.quick, clean: true);
    final changed = m.copyWith(modifiedAt: m.modifiedAt + 1);
    expect(await coverage.mode(changed), isNull);
  });
}
