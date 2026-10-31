// The training export on fake media: which detections of a person are picked, how the originals
// are cut, what the zip holds, and that a stopped export continues instead of starting over.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/platform/crop_source.dart';
import 'package:antigravity_mobile/domain/export/crop_math.dart';
import 'package:antigravity_mobile/domain/export/export_selection.dart';
import 'package:antigravity_mobile/domain/export/training_export.dart';
import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/seed.dart';

class _Crop {
  _Crop(this.asset, this.timeMs, this.rect, this.out);
  final String asset;
  final int? timeMs;
  final PxRect rect;
  final (int, int) out;
}

/// Originals by asset id; a missing id is "deleted from the phone".
class FakeCropSource implements CropSource {
  FakeCropSource(this.sizes, {this.orientation = 1});

  final Map<String, (int, int)> sizes;
  final int orientation;
  final opens = <String>[];
  final crops = <_Crop>[];
  void Function()? afterCrop;
  Set<String> unreadable = {};
  String? _asset;
  int? _time;
  var closed = 0;

  @override
  Future<SourceFrame?> open({
    required String assetId,
    required bool video,
    int? timeMs,
  }) async {
    opens.add('$assetId@${timeMs ?? '-'}');
    final size = sizes[assetId];
    if (size == null) return null;
    _asset = assetId;
    _time = timeMs;
    return SourceFrame(
      rawWidth: size.$1,
      rawHeight: size.$2,
      orientation: orientation,
    );
  }

  @override
  Future<Uint8List?> crop(
    SourceFrame frame,
    PxRect rect, {
    required int outWidth,
    required int outHeight,
    int quality = 95,
  }) async {
    if (unreadable.contains(_asset)) {
      afterCrop?.call();
      return null;
    }
    crops.add(_Crop(_asset!, _time, rect, (outWidth, outHeight)));
    afterCrop?.call();
    return Uint8List.fromList([0xFF, 0xD8, outWidth & 255, outHeight & 255]);
  }

  @override
  Future<void> close() async => closed++;
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  late int person;
  late int other;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_train_export_');
    person = await seedPerson(db, name: 'Sara');
    other = await seedPerson(db, name: 'Other');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  TrainingExporter exporter(FakeCropSource source) => TrainingExporter(
    queries: TrainingExportQueries(db),
    source: source,
    workRoot: Directory('${tmp.path}/work'),
    outputDir: Directory('${tmp.path}/out'),
    clock: () => DateTime(2026, 10, 31, 12, 30, 5),
  );

  Future<void> setTime(int refId, String kind, int timestampMs) =>
      db.customStatement(
        'UPDATE media_detections SET timestamp_ms = $timestampMs '
        "WHERE ref_id = $refId AND kind = '$kind'",
      );

  Future<int> photoFace(String asset, int personId, {double size = 0.1}) async {
    final m = await seedMedia(db, asset: asset, width: 4000, height: 3000);
    return seedFace(
      db,
      mediaId: m,
      personId: personId,
      x: 0.4,
      y: 0.4,
      w: size,
      h: size * 4 / 3,
    );
  }

  Archive readZip(File zip) => ZipDecoder().decodeBytes(zip.readAsBytesSync());

  Map<String, dynamic> manifestOf(File zip) =>
      jsonDecode(
            utf8.decode(
              readZip(
                zip,
              ).files.firstWhere((f) => f.name == 'manifest.json').content,
            ),
          )
          as Map<String, dynamic>;

  test(
    'exports only the persons own faces, cut from the original at native size',
    () async {
      await photoFace('1', person);
      await photoFace('2', other);
      await photoFace('3', person, size: 0.01); // 40 px: too small
      final source = FakeCropSource({
        '1': (4000, 3000),
        '2': (4000, 3000),
        '3': (4000, 3000),
      });
      final result = await exporter(
        source,
      ).run(TrainingExportOptions(personId: person), personName: 'Sara');
      expect(result.exported, 1);
      expect(source.opens, [
        '1@-',
      ]); // the other person and the tiny face are never opened
      final crop = source.crops.single;
      // face 400 x 400 px (0.1 * 4000, 0.1333 * 3000) -> square 640 px at native resolution
      expect(crop.rect.width, 640);
      expect(crop.rect.height, 640);
      expect(crop.out, (512, 512));
      final zip = result.zip!;
      expect(zip.path, endsWith('Sara_training_20261031-123005.zip'));
      final names = readZip(zip).files.map((f) => f.name).toSet();
      expect(names, {
        'faces/face_m1_t00000000_d1.jpg',
        'manifest.json',
        'manifest.csv',
      });
    },
  );

  test('the manifest records asset, frame, time, box and crop', () async {
    final m = await seedMedia(
      db,
      asset: '77',
      kind: 'video',
      width: 3840,
      height: 2160,
    );
    final f = await seedFace(
      db,
      mediaId: m,
      personId: person,
      x: 0.45,
      y: 0.3,
      w: 0.05,
      h: 0.09,
      frameNumber: 90,
    );
    await setTime(f, 'f', 3000);
    final result = await exporter(
      FakeCropSource({'77': (3840, 2160)}),
    ).run(TrainingExportOptions(personId: person), personName: 'Sara');
    final json = manifestOf(result.zip!);
    final item = (json['items'] as List).single as Map<String, dynamic>;
    expect(item['assetId'], '77');
    expect(item['mediaKind'], 'video');
    expect(item['timestampMs'], 3000);
    expect(item['sourceSize'], [3840, 2160]);
    expect(item['box'], [0.45, 0.3, 0.05, 0.09]);
    expect(item['outputSize'], [512, 512]);
    expect(item['crop'], isA<List>());
    expect((json['options'] as Map)['faceSize'], 512);
    final csv = utf8.decode(
      readZip(
        result.zip!,
      ).files.firstWhere((f) => f.name == 'manifest.csv').content,
    );
    expect(csv.split('\n').first, startsWith('file,status,kind'));
    expect(csv, contains(',77,'));
  });

  test(
    'a video is sampled across its length; faces and bodies of one time share a decode',
    () async {
      final m = await seedMedia(
        db,
        asset: '5',
        kind: 'video',
        width: 1920,
        height: 1080,
      );
      for (var i = 0; i < 30; i++) {
        final f = await seedFace(
          db,
          mediaId: m,
          personId: person,
          x: 0.4,
          y: 0.3,
          w: 0.12,
          h: 0.2,
        );
        await setTime(f, 'f', i * 4000);
        // the body only knows its face: it belongs to the person through the link
        final b = await seedBody(db, mediaId: m, faceId: f, frameNumber: i);
        await setTime(b, 'b', i * 4000);
      }
      final source = FakeCropSource({'5': (1920, 1080)});
      final result = await exporter(source).run(
        TrainingExportOptions(
          personId: person,
          bodies: true,
          selection: const ExportSelectionOptions(
            maxPerVideo: 6,
            minBodyHeightPx: 100,
          ),
        ),
      );
      expect(result.exported, 12);
      expect(source.opens.length, source.opens.toSet().length);
      final times = source.crops.map((c) => c.timeMs!).toSet().toList()..sort();
      expect(times.last - times.first, greaterThan(60000));
      final bodies = source.crops.where((c) => c.out.$1 != c.out.$2);
      expect(bodies, isNotEmpty);
      expect(bodies.every((c) => c.out.$2 <= 1024), isTrue);
    },
  );

  test('a deleted original is counted, not fatal', () async {
    await photoFace('1', person);
    await photoFace('2', person);
    final result = await exporter(
      FakeCropSource({'1': (4000, 3000)}),
    ).run(TrainingExportOptions(personId: person));
    expect(result.exported, 1);
    expect(result.missing, 1);
    final statuses = (manifestOf(result.zip!)['items'] as List).map(
      (i) => (i as Map)['status'],
    );
    expect(statuses, containsAll(['ok', 'missing']));
  });

  test('nothing exportable gives no zip', () async {
    await photoFace('1', person);
    final result = await exporter(
      FakeCropSource({}),
    ).run(TrainingExportOptions(personId: person));
    expect(result.zip, isNull);
    expect(result.exported, 0);
    expect(result.missing, 1);
  });

  test(
    'cancel keeps the finished pictures and a second run only does the rest',
    () async {
      for (var i = 1; i <= 5; i++) {
        await photoFace('$i', person);
      }
      final sizes = {for (var i = 1; i <= 5; i++) '$i': (4000, 3000)};
      final first = FakeCropSource(sizes);
      final token = ExportCancelToken();
      first.afterCrop = () {
        if (first.crops.length == 2) token.cancel();
      };
      final stopped = await exporter(
        first,
      ).run(TrainingExportOptions(personId: person), cancel: token);
      expect(stopped.cancelled, isTrue);
      expect(stopped.zip, isNull);
      expect(first.crops.length, 2);

      final second = FakeCropSource(sizes);
      final result = await exporter(
        second,
      ).run(TrainingExportOptions(personId: person));
      expect(result.cancelled, isFalse);
      expect(
        second.crops.length,
        3,
        reason: 'the two finished pictures are not cut again',
      );
      expect(result.exported, 5);
      expect(
        readZip(
          result.zip!,
        ).files.where((f) => f.name.startsWith('faces/')).length,
        5,
      );
      expect(
        Directory('${tmp.path}/work').listSync(),
        isEmpty,
        reason: 'work folder removed after packing',
      );
    },
  );

  test(
    'a failed crop is tried again on resume, and a vanished file is cut again',
    () async {
      await photoFace('1', person);
      await photoFace('2', person);
      final sizes = {'1': (4000, 3000), '2': (4000, 3000)};
      final first = FakeCropSource(sizes)..unreadable = {'2'};
      final token = ExportCancelToken();
      first.afterCrop = token.cancel; // stop before packing
      final options = TrainingExportOptions(personId: person);
      final r1 = await exporter(first).run(options, cancel: token);
      expect(r1.cancelled, isTrue);

      final work = exporter(first).workDir(options);
      for (final f
          in work
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg'))) {
        f.deleteSync();
      }
      final second = FakeCropSource(sizes);
      final r2 = await exporter(second).run(options);
      expect(r2.exported, 2);
      expect(second.crops.length, 2);
    },
  );

  test('a manifest cut off mid-line by a killed app is tolerated', () async {
    await photoFace('1', person);
    final options = TrainingExportOptions(personId: person);
    final ex = exporter(FakeCropSource({'1': (4000, 3000)}));
    final dir = ex.workDir(options)..createSync(recursive: true);
    File(
      '${dir.path}/manifest.jsonl',
    ).writeAsStringSync('{"key":"f1","status":"o');
    final result = await ex.run(options);
    expect(result.exported, 1);
  });

  test('a rotated photo is judged and cut in upright pixels', () async {
    await photoFace('1', person);
    // EXIF 6: stored 4000 x 3000 shows upright 3000 x 4000, so the face box is 300 x 533 px
    final source = FakeCropSource({'1': (4000, 3000)}, orientation: 6);
    final result = await exporter(
      source,
    ).run(TrainingExportOptions(personId: person));
    expect(result.exported, 1);
    expect(source.crops.single.rect.width, (533.33 * 1.6).round());
    expect(source.crops.single.rect.height, source.crops.single.rect.width);
  });

  test('hidden faces are never exported', () async {
    final id = await photoFace('1', person);
    await db.customStatement('UPDATE faces SET hidden = 1 WHERE id = $id');
    final result = await exporter(
      FakeCropSource({'1': (4000, 3000)}),
    ).run(TrainingExportOptions(personId: person));
    expect(result.exported, 0);
    expect(result.zip, isNull);
  });
}
