import 'package:flutter/services.dart';

class OrganizeAsset {
  const OrganizeAsset(this.assetId, this.kind);
  final String assetId, kind;
  Map<String, Object?> toJson() => {'assetId': assetId, 'kind': kind};
}

class OriginalMediaInfo {
  const OriginalMediaInfo({
    required this.assetId,
    required this.name,
    required this.path,
    required this.modifiedAt,
    required this.size,
    this.mimeType = '',
    this.error,
  });
  final String assetId, name, path, mimeType;
  final int modifiedAt, size;
  final String? error;
  bool get available => error == null && name.isNotEmpty;
  factory OriginalMediaInfo.fromJson(Map<Object?, Object?> j) =>
      OriginalMediaInfo(
        assetId: j['assetId'] as String,
        name: j['name'] as String? ?? '',
        path: j['path'] as String? ?? '',
        modifiedAt: (j['modifiedAt'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        mimeType: j['mimeType'] as String? ?? '',
        error: j['error'] as String?,
      );
}

class OriginalMediaMove {
  const OriginalMediaMove({
    required this.asset,
    required this.source,
    required this.targetName,
    required this.targetPath,
  });
  final OrganizeAsset asset;
  final OriginalMediaInfo source;
  final String targetName, targetPath;
  Map<String, Object?> toJson() => {
    ...asset.toJson(),
    'sourceName': source.name,
    'sourcePath': source.path,
    'sourceModifiedAt': source.modifiedAt,
    'sourceSize': source.size,
    'targetName': targetName,
    'targetPath': targetPath,
  };
}

class OriginalMoveResult {
  const OriginalMoveResult({
    required this.assetId,
    required this.status,
    this.actual,
    this.detail,
  });
  final String assetId, status;
  final OriginalMediaInfo? actual;
  final String? detail;
  bool get moved => status == 'moved' || status == 'already';
  factory OriginalMoveResult.fromJson(Map<Object?, Object?> j) =>
      OriginalMoveResult(
        assetId: j['assetId'] as String,
        status: j['status'] as String,
        detail: j['detail'] as String?,
        actual: j['actual'] is Map
            ? OriginalMediaInfo.fromJson(j['actual'] as Map)
            : null,
      );
}

abstract interface class MediaOrganizerBridge {
  Future<List<OriginalMediaInfo>> inspect(List<OrganizeAsset> assets);
  Future<List<OriginalMoveResult>> preflight(List<OriginalMediaMove> moves);
  Future<List<OriginalMoveResult>> move(List<OriginalMediaMove> moves);
}

class AndroidMediaOrganizer implements MediaOrganizerBridge {
  const AndroidMediaOrganizer();
  static const channel = MethodChannel('antigravity/media_organizer');
  @override
  Future<List<OriginalMediaInfo>> inspect(List<OrganizeAsset> assets) async => [
    for (final j
        in await channel.invokeListMethod<Object?>('inspect', {
              'items': [for (final a in assets) a.toJson()],
            }) ??
            [])
      OriginalMediaInfo.fromJson(j as Map),
  ];
  Future<List<OriginalMoveResult>> _call(
    String method,
    List<OriginalMediaMove> moves,
  ) async => [
    for (final j
        in await channel.invokeListMethod<Object?>(method, {
              'items': [for (final m in moves) m.toJson()],
            }) ??
            [])
      OriginalMoveResult.fromJson(j as Map),
  ];
  @override
  Future<List<OriginalMoveResult>> preflight(List<OriginalMediaMove> moves) =>
      _call('preflight', moves);
  @override
  Future<List<OriginalMoveResult>> move(List<OriginalMediaMove> moves) =>
      _call('move', moves);

  /// Whether Android lets this app move photos without a confirmation sheet ("All files access" or
  /// "Media management").
  Future<bool> canMoveWithoutPrompt() async {
    try {
      return await channel.invokeMethod<bool>('canManageMedia') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// "All files access": person folders go in the top-level Your Gallery folder, with their .json files.
  Future<bool> hasAllFilesAccess() async {
    try {
      return await channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens Android's "All files access" page for this app. False when it cannot be opened.
  Future<bool> requestAllFilesAccess() async {
    try {
      return await channel.invokeMethod<bool>('requestAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system page where the user grants that access once. False when it cannot be opened.
  Future<bool> requestMoveWithoutPrompt() async {
    try {
      return await channel.invokeMethod<bool>('requestManageMedia') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
