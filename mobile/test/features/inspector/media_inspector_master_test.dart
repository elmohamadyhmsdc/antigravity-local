import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/platform/media_organizer.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/corrections/body_link_guard.dart';
import 'package:antigravity_mobile/domain/corrections/correction_service.dart';
import 'package:antigravity_mobile/domain/corrections/corrections_queries.dart';
import 'package:antigravity_mobile/domain/organization/dynamic_auto_organizer.dart';
import 'package:antigravity_mobile/domain/organization/person_media_organizer.dart';
import 'package:antigravity_mobile/features/inspector/media_inspector.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOrganizerBridge implements MediaOrganizerBridge {
  @override
  Future<List<OriginalMediaInfo>> inspect(List<OrganizeAsset> assets) async => [];

  @override
  Future<List<OriginalMoveResult>> preflight(List<OriginalMediaMove> moves) async => [];

  @override
  Future<List<OriginalMoveResult>> move(List<OriginalMediaMove> moves) async => [];
}

class SpyAutoOrganizer extends DynamicAutoOrganizer {
  SpyAutoOrganizer({required super.db, required super.organizer});

  int? lastExplicitMasterId;

  @override
  Future<OriginalMoveResult?> setMasterPerson(
    int mediaId,
    int personId, {
    String? rootDirectory,
  }) async {
    lastExplicitMasterId = personId;
    return null;
  }
}

void main() {
  late AppDatabase db;
  late PeopleRepository peopleRepo;
  late BodyLinkGuard bodyLinkGuard;
  late CorrectionService correctionService;
  late CorrectionsQueries correctionsQueries;
  late SpyAutoOrganizer spyAutoOrganizer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    peopleRepo = PeopleRepository(db, FileStore(Directory.systemTemp));
    bodyLinkGuard = BodyLinkGuard(db);
    correctionService = CorrectionService(
      db: db,
      peopleRepo: peopleRepo,
      bodyLinkGuard: bodyLinkGuard,
    );
    correctionsQueries = CorrectionsQueries(db);
    final bridge = FakeOrganizerBridge();
    final organizer = PersonMediaOrganizer(db: db, bridge: bridge);
    spyAutoOrganizer = SpyAutoOrganizer(db: db, organizer: organizer);
  });

  tearDown(() async => db.close());

  testWidgets('MediaInspector displays Master badge and allows switching primary owner', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = MediaRow(
      id: 1,
      assetId: 'asset_multi_1',
      kind: 'photo',
      sizeBytes: 1024,
      modifiedAt: 0,
      scanStatus: 'done',
      scanVersion: 1,
      lastScannedFrame: 0,
      scanAttempts: 0,
      illustrated: false,
      isSensitive: false,
      sensitiveVersion: 0,
      bodyEmbeddingVersion: 0,
      garmentVersion: 0,
      width: 1920,
      height: 1080,
    );

    // Person 1 has larger face box (area 0.4*0.4 = 0.16) -> default Master
    const f1 = MediaDetection(
      id: 10,
      kind: 'f',
      refId: 101,
      x: 0.1,
      y: 0.1,
      w: 0.4,
      h: 0.4,
      personId: 1,
      cropPath: null,
    );

    // Person 2 has smaller face box (area 0.2*0.2 = 0.04)
    const f2 = MediaDetection(
      id: 20,
      kind: 'f',
      refId: 201,
      x: 0.6,
      y: 0.2,
      w: 0.2,
      h: 0.2,
      personId: 2,
      cropPath: null,
    );

    final people = {
      1: PersonSummary(
        id: 1,
        name: 'Luffy',
        faceCount: 5,
        avatarCropPath: null,
        createdAt: DateTime.now(),
        hidden: false,
        favorite: false,
        pinned: false,
        groupingLocked: false,
        kind: 'person',
      ),
      2: PersonSummary(
        id: 2,
        name: 'Zoro',
        faceCount: 3,
        avatarCropPath: null,
        createdAt: DateTime.now(),
        hidden: false,
        favorite: false,
        pinned: false,
        groupingLocked: false,
        kind: 'person',
      ),
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          peopleRepositoryProvider.overrideWithValue(peopleRepo),
          bodyLinkGuardProvider.overrideWithValue(bodyLinkGuard),
          correctionServiceProvider.overrideWithValue(correctionService),
          correctionsQueriesProvider.overrideWithValue(correctionsQueries),
          dynamicAutoOrganizerProvider.overrideWithValue(spyAutoOrganizer),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaInspectorContent(
              media: media,
              faces: const [f1, f2],
              bodies: const [],
              people: people,
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Master badge on Luffy (person 1)
    expect(find.byKey(const Key('master-badge-1')), findsOneWidget);
    expect(find.byKey(const Key('master-badge-2')), findsNothing);

    // Verify option to set Zoro as Master
    final setMasterFinder = find.byKey(const Key('who-set-master-2'));
    expect(setMasterFinder, findsOneWidget);

    // Tap set as primary owner on Zoro
    await tester.tap(setMasterFinder);
    await tester.pumpAndSettle();

    // Verify Zoro is now master and auto organizer was called
    expect(spyAutoOrganizer.lastExplicitMasterId, 2);
    expect(find.byKey(const Key('master-badge-2')), findsOneWidget);
    expect(find.byKey(const Key('master-badge-1')), findsNothing);
  });
}
