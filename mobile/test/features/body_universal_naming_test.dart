import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/features/bodies/body_naming.dart';
import 'package:antigravity_mobile/features/bodies/body_areas.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/providers.dart';
import '../support/seed.dart';

void main() {
  test('renamePoseCategory and renameOutfitCategory update names in database', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed pose category
    final poseId = await db.into(db.poseCategories).insert(
      PoseCategoriesCompanion.insert(
        name: 'Initial Pose',
        exemplarFeature: Uint8List(0),
        exemplarMask: 0,
        exemplarScaleSource: 'torso',
        threshold: 0.75,
        createdAt: 1000,
      ),
    );

    // Seed outfit category
    final outfitId = await db.into(db.outfitCategories).insert(
      OutfitCategoriesCompanion.insert(
        name: 'Initial Outfit',
        exemplarAppearance: Uint8List(0),
        threshold: 0.75,
        createdAt: 1000,
      ),
    );

    expect(await renamePoseCategory(db, poseId, 'Renamed Pose'), isTrue);
    final updatedPose = await (db.select(db.poseCategories)..where((c) => c.id.equals(poseId))).getSingle();
    expect(updatedPose.name, 'Renamed Pose');

    expect(await renameOutfitCategory(db, outfitId, 'Renamed Outfit'), isTrue);
    final updatedOutfit = await (db.select(db.outfitCategories)..where((c) => c.id.equals(outfitId))).getSingle();
    expect(updatedOutfit.name, 'Renamed Outfit');
  });

  testWidgets('BodyAreasTab renders custom cluster name and handles rename', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Set cluster enabled
    await db.putSetting('body_clusters_enabled', 'true');
    await db.putSetting('cluster.name.1', 'Dragon Chest Tattoo');

    // Seed body cluster
    await db.into(db.bodyClusters).insert(
      BodyClustersCompanion.insert(
        id: const Value(1),
        clusterType: 'chest',
        centroidEmbedding: Uint8List(384 * 4),
        bodyCount: const Value(3),
        createdAt: 1000,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: BodyAreasTab(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify custom name is rendered
    expect(find.text('Dragon Chest Tattoo'), findsOneWidget);
    expect(find.byKey(const Key('rename-cluster-1')), findsOneWidget);

    // Tap rename button
    await tester.tap(find.byKey(const Key('rename-cluster-1')));
    await tester.pumpAndSettle();

    // Verify dialog opens
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('BodyAreasTab opens BodyInspectionSheet when tapping cluster crop', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.putSetting('body_clusters_enabled', 'true');
    await db.into(db.bodyClusters).insert(
      BodyClustersCompanion.insert(
        id: const Value(1),
        clusterType: 'chest',
        centroidEmbedding: Uint8List(384 * 4),
        bodyCount: const Value(1),
        createdAt: 1000,
      ),
    );

    final mediaId = await seedMedia(db, asset: 'm1');
    final bodyId = await seedBody(db, mediaId: mediaId, cropPath: null);
    await (db.update(db.bodies)..where((b) => b.id.equals(bodyId))).write(
      const BodiesCompanion(
        chestClusterId: Value(1),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: BodyAreasTab(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('cluster-body-$bodyId')), findsOneWidget);
    await tester.tap(find.byKey(Key('cluster-body-$bodyId')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('toggle-skeleton-btn')), findsOneWidget);
    expect(find.byKey(const Key('toggle-area-btn')), findsOneWidget);
  });
}
