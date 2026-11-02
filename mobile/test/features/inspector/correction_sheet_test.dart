import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/corrections/body_link_guard.dart';
import 'package:antigravity_mobile/domain/corrections/correction_service.dart';
import 'package:antigravity_mobile/domain/corrections/correction_target.dart';
import 'package:antigravity_mobile/features/inspector/correction_sheet.dart';
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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    peopleRepo = PeopleRepository(db, FileStore(Directory.systemTemp));
    bodyLinkGuard = BodyLinkGuard(db);
    correctionService = CorrectionService(
      db: db,
      peopleRepo: peopleRepo,
      bodyLinkGuard: bodyLinkGuard,
    );
  });

  tearDown(() async => db.close());

  Widget buildTestWidget({
    required CorrectionTarget target,
    bool isVideo = false,
    VoidCallback? onApplied,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        peopleRepositoryProvider.overrideWithValue(peopleRepo),
        bodyLinkGuardProvider.overrideWithValue(bodyLinkGuard),
        correctionServiceProvider.overrideWithValue(correctionService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CorrectionSheet(
            target: target,
            isVideo: isVideo,
            title: 'Test Correction',
            onApplied: onApplied,
          ),
        ),
      ),
    );
  }

  testWidgets('CorrectionSheet renders allowed verbs for FaceLinkTarget', (
    tester,
  ) async {
    const target = FaceLinkTarget(faceId: 1, mediaId: 10, personId: 2);

    await tester.pumpWidget(buildTestWidget(target: target));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('correction-sheet')), findsOneWidget);
    expect(find.byKey(const Key('correction-title')), findsOneWidget);
    expect(find.text('Test Correction'), findsOneWidget);

    // Verbs for FaceLinkTarget
    expect(find.byKey(const Key('correction-verb-reassign')), findsOneWidget);
    expect(
      find.byKey(const Key('correction-verb-notThisPerson')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('correction-verb-belongsToNoOne')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('correction-verb-notARealThing')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('correction-verb-unlink')), findsOneWidget);
    expect(find.byKey(const Key('correction-verb-confirm')), findsOneWidget);
  });

  testWidgets('CorrectionSheet displays scope picker when isVideo is true', (
    tester,
  ) async {
    const target = BodyLinkTarget(bodyId: 5, mediaId: 20, personId: 3);

    await tester.pumpWidget(buildTestWidget(target: target, isVideo: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('correction-scope-picker')), findsOneWidget);
    expect(find.text('This appearance'), findsOneWidget);
    expect(find.text('Whole video'), findsOneWidget);
  });
}
