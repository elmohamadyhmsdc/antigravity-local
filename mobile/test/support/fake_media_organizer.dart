import 'package:antigravity_mobile/data/platform/media_organizer.dart';

class FakeMediaOrganizer implements MediaOrganizerBridge {
  final originals = <String, OriginalMediaInfo>{};
  final moves = <List<OriginalMediaMove>>[];
  bool cancel = false;
  int? crashAfter;
  Future<void> Function()? beforeWrite;

  void seed(
    String asset, {
    String name = 'camera.jpg',
    String path = 'DCIM/Camera/',
    int modifiedAt = 1000,
  }) {
    originals[asset] = OriginalMediaInfo(
      assetId: asset,
      name: name,
      path: path,
      modifiedAt: modifiedAt,
      size: 150,
      mimeType: name.endsWith('mp4') ? 'video/mp4' : 'image/jpeg',
    );
  }

  @override
  Future<List<OriginalMediaInfo>> inspect(List<OrganizeAsset> assets) async => [
    for (final a in assets)
      originals[a.assetId] ??
          OriginalMediaInfo(
            assetId: a.assetId,
            name: '',
            path: '',
            modifiedAt: 0,
            size: 0,
            error: 'missing',
          ),
  ];
  OriginalMoveResult check(OriginalMediaMove move) {
    final actual = originals[move.asset.assetId];
    if (actual == null) {
      return OriginalMoveResult(assetId: move.asset.assetId, status: 'missing');
    }
    if (actual.name == move.targetName && actual.path == move.targetPath) {
      return OriginalMoveResult(
        assetId: actual.assetId,
        status: 'already',
        actual: actual,
      );
    }
    if (actual.name != move.source.name ||
        actual.path != move.source.path ||
        actual.modifiedAt != move.source.modifiedAt ||
        actual.size != move.source.size) {
      return OriginalMoveResult(
        assetId: actual.assetId,
        status: 'stale',
        actual: actual,
      );
    }
    if (originals.values.any(
      (o) =>
          o.assetId != actual.assetId &&
          o.name == move.targetName &&
          o.path == move.targetPath,
    )) {
      return OriginalMoveResult(
        assetId: actual.assetId,
        status: 'conflict',
        actual: actual,
      );
    }
    return OriginalMoveResult(
      assetId: actual.assetId,
      status: 'ready',
      actual: actual,
    );
  }

  @override
  Future<List<OriginalMoveResult>> preflight(
    List<OriginalMediaMove> items,
  ) async => items.map(check).toList();
  @override
  Future<List<OriginalMoveResult>> move(List<OriginalMediaMove> items) async {
    moves.add(items);
    await beforeWrite?.call();
    final results = <OriginalMoveResult>[];
    for (final item in items) {
      if (cancel) {
        results.add(
          OriginalMoveResult(assetId: item.asset.assetId, status: 'cancelled'),
        );
        continue;
      }
      final checked = check(item);
      if (checked.status != 'ready') {
        results.add(checked);
        continue;
      }
      final actual = OriginalMediaInfo(
        assetId: item.asset.assetId,
        name: item.targetName,
        path: item.targetPath,
        modifiedAt: 2000,
        size: item.source.size,
      );
      originals[actual.assetId] = actual;
      if (crashAfter != null && results.length + 1 >= crashAfter!) {
        throw StateError('Simulated app termination after MediaStore update');
      }
      results.add(
        OriginalMoveResult(
          assetId: actual.assetId,
          status: 'moved',
          actual: actual,
        ),
      );
    }
    return results;
  }
}
