import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/corrections/body_link_guard.dart';
import 'package:antigravity_mobile/domain/corrections/correction_service.dart';
import 'package:antigravity_mobile/domain/corrections/corrections_queries.dart';
import 'package:antigravity_mobile/features/inspector/media_inspector.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PeopleRepository peopleRepo;
  late BodyLinkGuard bodyLinkGuard;
  late CorrectionService correctionService;
  late CorrectionsQueries correctionsQueries;

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
  });

  tearDown(() async => db.close());

  Widget buildTestWidget({
    required MediaRow media,
    required List<MediaDetection> faces,
    required List<MediaDetection> bodies,
    required Map<int, PersonSummary> people,
    ValueChanged<MediaDetection>? onSelectDetection,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        peopleRepositoryProvider.overrideWithValue(peopleRepo),
        bodyLinkGuardProvider.overrideWithValue(bodyLinkGuard),
        correctionServiceProvider.overrideWithValue(correctionService),
        correctionsQueriesProvider.overrideWithValue(correctionsQueries),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaInspectorContent(
            media: media,
            faces: faces,
            bodies: bodies,
            people: people,
            scrollController: ScrollController(),
            onSelectDetection: onSelectDetection,
          ),
        ),
      ),
    );
  }

  testWidgets('MediaInspectorContent renders peek bar and sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final media = MediaRow(
      id: 1,
      assetId: 'asset_1',
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

    const f1 = MediaDetection(
      id: 10,
      kind: 'f',
      refId: 1,
      x: 0.1,
      y: 0.1,
      w: 0.1,
      h: 0.1,
      personId: 100,
      cropPath: null,
    );

    const b1 = MediaDetection(
      id: 20,
      kind: 'b',
      refId: 2,
      x: 0.1,
      y: 0.2,
      w: 0.3,
      h: 0.6,
      personId: null,
      cropPath: null,
    );

    final people = {
      100: PersonSummary(
        id: 100,
        name: 'Sara',
        kind: 'person',
        faceCount: 1,
        avatarCropPath: null,
        createdAt: DateTime(2026),
      ),
    };

    MediaDetection? tappedDetection;

    await tester.pumpWidget(
      buildTestWidget(
        media: media,
        faces: const [f1],
        bodies: const [b1],
        people: people,
        onSelectDetection: (d) => tappedDetection = d,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Peek bar
    expect(find.byKey(const Key('inspector-peek-bar')), findsOneWidget);
    expect(find.byKey(const Key('peek-chip-10')), findsOneWidget);
    expect(find.byKey(const Key('peek-chip-20')), findsOneWidget);

    // Tap peek chip 10
    await tester.tap(find.byKey(const Key('peek-chip-10')));
    expect(tappedDetection?.id, 10);

    // 2. Sections
    expect(find.text('Who is here'), findsOneWidget);
    expect(find.byKey(const Key('inspector-person-100')), findsOneWidget);
    expect(find.byKey(const Key('inspector-unassigned-group')), findsOneWidget);

    expect(find.text('Links'), findsOneWidget);
    expect(find.text('Activities & Marks'), findsOneWidget);
    expect(find.byKey(const Key('inspect-mark-tattoo')), findsOneWidget);

    expect(find.text('Create with AI'), findsOneWidget);
    expect(find.byKey(const Key('inspect-create-reface')), findsOneWidget);
    expect(find.byKey(const Key('inspect-create-restyle')), findsOneWidget);

    expect(find.text('File info'), findsOneWidget);
    expect(find.byKey(const Key('inspect-redetect')), findsOneWidget);
    expect(find.byKey(const Key('inspect-analyze-now')), findsOneWidget);
  });
}
