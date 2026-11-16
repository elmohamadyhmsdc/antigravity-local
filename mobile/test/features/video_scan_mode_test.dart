import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/core/router.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/data/repositories/video_scan_coverage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest('video preferences default to quick and expose detailed sampling on request', (tester, env) async {
    await env.pump(tester, extra: [initialLocationProvider.overrideWithValue(Routes.settingsLibrary)]);
    final section = find.byKey(const Key('library-scan-section'));
    await revealForTap(tester, section);
    await tester.tapAt(tester.getTopLeft(section) + const Offset(120, 28));
    await tester.pumpAndSettle();
    final picker = find.byKey(const Key('video-scan-mode'));
    await revealForTap(tester, picker);
    expect((await env.settingsSnapshot()).videoScanMode, VideoScanMode.quick);
    expect(find.byKey(const Key('adaptive-video-sampling')), findsNothing);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detailed scan').last);
    await tester.pumpAndSettle();
    expect((await env.settingsSnapshot()).videoScanMode, VideoScanMode.detailed);
    expect(find.byKey(const Key('adaptive-video-sampling')), findsOneWidget);
  }, session: testSession);

  appTest('quick video has a coverage label and can queue an individual detailed pass', (tester, env) async {
    final id = await seedMedia(env.db, kind: 'video', asset: 'quick');
    final photo = await seedMedia(env.db, asset: 'finished-photo');
    final media = (await LibraryRepository(env.db).mediaById(id))!;
    final coverage = VideoScanCoverage(env.db);
    await coverage.complete(media, VideoScanMode.quick, clean: true);
    await env.pump(tester, extra: [initialLocationProvider.overrideWithValue('${Routes.media}/$id')]);
    expect(find.text('Quick scan complete'), findsOneWidget);
    await tester.tap(find.byKey(const Key('media-more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('media-detailed-scan')));
    await tester.pumpAndSettle();
    expect(await coverage.detailRequested(media), isTrue);
    expect((await LibraryRepository(env.db).mediaById(photo))!.scanStatus, 'done');
  }, session: testSession);

  appTest('remaining queue can resume without choosing sources or resetting finished photos', (tester, env) async {
    final photo = await seedMedia(env.db, asset: 'finished-photo');
    await seedMedia(env.db, kind: 'video', asset: 'waiting-video', status: 'pending');
    await env.pump(tester, extra: [initialLocationProvider.overrideWithValue(Routes.settingsLibrary)]);
    expect((await env.settingsSnapshot()).albumIds, isEmpty);
    await tester.tap(find.byKey(const Key('scan-continue-queue')));
    await tester.pumpAndSettle();
    expect((await LibraryRepository(env.db).mediaById(photo))!.scanStatus, 'done');
    expect(env.api.analyzeCalls, isEmpty);
  }, session: testSession);
}
