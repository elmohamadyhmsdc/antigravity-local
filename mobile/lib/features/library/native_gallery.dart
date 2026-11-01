import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/router.dart';
import '../../data/media/media_library.dart';
import '../../domain/scan/scan_state.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../scan/scan_progress_card.dart';
import '../media/media_screen.dart';
import '../media/video_media_view.dart';
import '../shared/empty_state.dart';

/// Browses MediaStore independently of analysis; only loaded assets are registered.
class NativeGalleryState {
  const NativeGalleryState({
    this.assets = const [],
    this.assetIds = const {},
    this.loading = true,
    this.more = true,
    this.access = true,
    this.limited = false,
    this.permissionIntro = false,
    this.error,
    this.albumId,
  });

  final List<AssetInfo> assets;
  final Set<String> assetIds;
  final bool loading;
  final bool more;
  final bool access;
  final bool limited;
  final bool permissionIntro;
  final Object? error;
  final String? albumId;

  NativeGalleryState copyWith({
    List<AssetInfo>? assets,
    Set<String>? assetIds,
    bool? loading,
    bool? more,
    bool? access,
    bool? limited,
    bool? permissionIntro,
    Object? error,
    bool clearError = false,
    String? albumId,
  }) {
    return NativeGalleryState(
      assets: assets ?? this.assets,
      assetIds: assetIds ?? this.assetIds,
      loading: loading ?? this.loading,
      more: more ?? this.more,
      access: access ?? this.access,
      limited: limited ?? this.limited,
      permissionIntro: permissionIntro ?? this.permissionIntro,
      error: clearError ? null : (error ?? this.error),
      albumId: albumId ?? this.albumId,
    );
  }
}

class NativeGalleryNotifier extends Notifier<NativeGalleryState> {
  StreamIterator<List<AssetInfo>>? _pages;
  Future<List<AssetInfo>>? _pending;
  final _albumCache = <String, NativeGalleryState>{};

  @override
  NativeGalleryState build() {
    ref.onDispose(() {
      _pages?.cancel();
    });
    return const NativeGalleryState();
  }

  Future<void> open({AlbumInfo? album, bool explained = false}) async {
    final targetId = album?.id ?? 'all';
    if (state.albumId == targetId && state.assets.isNotEmpty && state.error == null) {
      return;
    }
    if (_albumCache.containsKey(targetId) && _albumCache[targetId]!.assets.isNotEmpty) {
      state = _albumCache[targetId]!;
      return;
    }
    state = state.copyWith(loading: true, clearError: true, albumId: targetId);
    try {
      final library = ref.read(mediaLibraryProvider);
      if (!explained && library is PhotoManagerLibrary) {
        final status = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption(),
        );
        if (status == PermissionState.notDetermined) {
          state = state.copyWith(permissionIntro: true, loading: false);
          return;
        }
      }
      final access = await library.requestAccess();
      if (!access) {
        state = state.copyWith(access: false, loading: false);
        return;
      }
      if (library is PhotoManagerLibrary) {
        final permState = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption(),
        );
        state = state.copyWith(limited: permState == PermissionState.limited);
      }
      final albums = album == null ? await library.albums() : <AlbumInfo>[album];
      final all = album ?? albums.where((a) => a.isAll).firstOrNull;
      if (all == null && albums.isNotEmpty) {
        throw const FormatException(
          'All photos are unavailable. Browse folders instead.',
        );
      }
      if (all == null) {
        state = state.copyWith(loading: false, more: false);
        _albumCache[targetId] = state;
        return;
      }
      await _pages?.cancel();
      _pages = StreamIterator(library.photos({all.id}, pageSize: 120));
      await loadNext();
    } catch (error) {
      state = state.copyWith(error: error, loading: false);
      _albumCache[targetId] = state;
    }
  }

  Future<List<AssetInfo>> loadNext() {
    if (_pending != null) return _pending!;
    if (!state.more || _pages == null) return Future.value(const []);
    state = state.copyWith(loading: true);
    final future = _readNext();
    _pending = future;
    return future.whenComplete(() => _pending = null);
  }

  Future<List<AssetInfo>> _readNext() async {
    try {
      final hasNext = await _pages!.moveNext();
      final batch = hasNext ? _pages!.current : <AssetInfo>[];
      final newAssetIds = Set<String>.from(state.assetIds);
      final newAssets = List<AssetInfo>.from(state.assets);
      for (final asset in batch) {
        if (newAssetIds.add(asset.id)) {
          newAssets.add(asset);
        }
      }
      state = state.copyWith(
        assets: newAssets,
        assetIds: newAssetIds,
        more: hasNext,
        loading: false,
      );
      _albumCache[state.albumId ?? 'all'] = state;
      return batch;
    } catch (error) {
      state = state.copyWith(error: error, loading: false);
      _albumCache[state.albumId ?? 'all'] = state;
      rethrow;
    }
  }

  Future<void> refresh({AlbumInfo? album}) async {
    await _pages?.cancel();
    _pages = null;
    final targetId = album?.id ?? 'all';
    _albumCache.remove(targetId);
    state = const NativeGalleryState();
    await open(album: album, explained: true);
  }
}

final nativeGalleryProvider =
    NotifierProvider<NativeGalleryNotifier, NativeGalleryState>(
  NativeGalleryNotifier.new,
);

class NativeGallery extends ConsumerStatefulWidget {
  const NativeGallery({super.key, this.album, this.kind});
  final AlbumInfo? album;
  final String? kind;
  @override
  ConsumerState<NativeGallery> createState() => _NativeGalleryState();
}

class _NativeGalleryState extends ConsumerState<NativeGallery> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(nativeGalleryProvider.notifier).open(album: widget.album);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    final state = ref.read(nativeGalleryProvider);
    if (state.error == null &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 900) {
      ref.read(nativeGalleryProvider.notifier).loadNext().ignore();
    }
  }

  Future<void> _openAsset(AssetInfo asset) async {
    try {
      final gallery = ref.read(nativeGalleryProvider);
      final visible = gallery.assets
          .where((asset) => widget.kind == null || asset.kind == widget.kind)
          .toList();
      var registered = gallery.assets.length;
      final rows = await ref
          .read(libraryRepositoryProvider)
          .ensureBrowsableAssets(visible);
      if (!mounted) return;
      final index = visible.indexWhere((a) => a.id == asset.id);
      if (index < 0 || index >= rows.length) return;
      final ids = [for (final row in rows) row.id];
      final repo = ref.read(libraryRepositoryProvider);
      await context.push(
        '${Routes.media}/${rows[index].id}',
        extra: MediaCollectionContext(
          ids: ids,
          loadMore: () async {
            final notifier = ref.read(nativeGalleryProvider.notifier);
            var end = ref.read(nativeGalleryProvider).assets.length;
            var assets = ref
                .read(nativeGalleryProvider)
                .assets
                .skip(registered)
                .where(
                  (asset) => widget.kind == null || asset.kind == widget.kind,
                )
                .toList();
            while (assets.isEmpty && ref.read(nativeGalleryProvider).more) {
              await notifier.loadNext();
              final currentAssets = ref.read(nativeGalleryProvider).assets;
              end = currentAssets.length;
              assets = currentAssets
                  .skip(registered)
                  .where(
                    (asset) => widget.kind == null || asset.kind == widget.kind,
                  )
                  .toList();
            }
            final nextRows = await repo.ensureBrowsableAssets(assets);
            registered = end;
            return [for (final row in nextRows) row.id];
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gallery = ref.watch(nativeGalleryProvider);
    if (gallery.permissionIntro) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'Your photos, first',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Allow photo access to browse photos and videos on this phone. You can connect a PC later.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.read(nativeGalleryProvider.notifier).open(album: widget.album, explained: true);
                },
                child: const Text('Allow photos'),
              ),
            ],
          ),
        ),
      );
    }
    if (!gallery.access) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Photo access needed',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Allow access to browse photos and videos.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref.read(nativeGalleryProvider.notifier).open(album: widget.album);
                },
                child: const Text('Allow photos'),
              ),
              if (ref.read(mediaLibraryProvider) is PhotoManagerLibrary)
                TextButton(
                  onPressed: PhotoManager.openSetting,
                  child: const Text('Open settings'),
                ),
            ],
          ),
        ),
      );
    }
    if (gallery.error != null && gallery.assets.isEmpty) {
      final message = gallery.error is FormatException
          ? (gallery.error as FormatException).message
          : 'Could not load photos.';
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            TextButton(
              onPressed: () {
                ref.read(nativeGalleryProvider.notifier).refresh(album: widget.album);
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (gallery.loading && gallery.assets.isEmpty) return const LoadingBox();
    if (gallery.assets.isEmpty) {
      return const Center(child: Text('No photos or videos available'));
    }
    final visible = gallery.assets
        .where((asset) => widget.kind == null || asset.kind == widget.kind)
        .toList();
    if (visible.isEmpty && !gallery.more) {
      return const Center(child: Text('No media matches this filter'));
    }
    final groups = <String, List<AssetInfo>>{};
    for (final asset in visible) {
      final date = asset.takenAt <= 0
          ? 'Unknown date'
          : DateFormat.yMMMd().format(
              DateTime.fromMillisecondsSinceEpoch(asset.takenAt),
            );
      groups.putIfAbsent(date, () => []).add(asset);
    }
    return Column(
      children: [
        if (gallery.limited)
          ListTile(
            title: const Text('Limited photo access'),
            subtitle: const Text(
              'Only selected photos and videos are visible.',
            ),
            trailing: TextButton(
              onPressed: () async {
                await PhotoManager.presentLimited(type: RequestType.common);
                ref.read(nativeGalleryProvider.notifier).refresh(album: widget.album);
              },
              child: const Text('Manage access'),
            ),
          ),
        Expanded(
          child: CustomScrollView(
            key: const Key('native-gallery-grid'),
            controller: _scroll,
            slivers: [
              for (final group in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Text(
                      group.key,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _tile(group.value[index]),
                    childCount: group.value.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                ),
              ],
              if (gallery.error != null)
                SliverToBoxAdapter(
                  child: Center(
                    child: TextButton(
                      onPressed: () {
                        ref.read(nativeGalleryProvider.notifier).refresh(album: widget.album);
                      },
                      child: const Text('Retry loading photos'),
                    ),
                  ),
                )
              else if (gallery.more && gallery.loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(AssetInfo asset) => InkWell(
    key: ValueKey('asset-${asset.id}'),
    onTap: () => _openAsset(asset),
    child: Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder(
          future: ref
              .read(thumbnailServiceProvider)
              .get(asset.id, width: asset.width, height: asset.height),
          builder: (context, snapshot) => snapshot.data == null
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.photo_outlined),
                )
              : Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
        ),
        if (asset.kind == 'video')
          Positioned(
            right: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                    Text(
                      videoTime(asset.durationMs ?? 0),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class GalleryFolders extends ConsumerWidget {
  const GalleryFolders({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(albumsProvider)
      .when(
        loading: () => const LoadingBox(),
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(albumsProvider)),
        data: (albums) {
          final folders = albums.where((a) => !a.isAll).toList();
          if (folders.isEmpty) {
            return const Center(child: Text('No folders available'));
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 52) / 2;
              final textHeight = MediaQuery.textScalerOf(context).scale(64);
              return GridView.builder(
                key: const PageStorageKey('gallery-folders'),
                padding: const EdgeInsets.all(20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: width * .75 + textHeight + 8,
                ),
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  return InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FolderScreen(album: folder),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: double.infinity,
                              child: _FolderCover(album: folder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          folder.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          folder.count.toString(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      );
}

class FolderScreen extends ConsumerStatefulWidget {
  const FolderScreen({super.key, required this.album});
  final AlbumInfo album;
  @override
  ConsumerState<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends ConsumerState<FolderScreen> {
  String? _kind;
  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final progress = ref.watch(scanProgressProvider).value;
    final active =
        (progress?.isActive ?? false) || progress?.phase == ScanPhase.paused;
    return Scaffold(
      appBar: AppBar(
        title: Text(album.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'settings') {
                context.push(Routes.sources);
                return;
              }
              if (active) {
                context.push(Routes.runningScan);
                return;
              }
              if (ref.read(mobileApiProvider) == null) {
                context.push(Routes.connection);
                return;
              }
              await startScan(ref, albumIds: {album.id});
              if (context.mounted) context.push(Routes.runningScan);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'analyze',
                child: Text(
                  active ? 'View current scan' : 'Analyze this folder',
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Scan settings'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${album.count} items'),
                const Spacer(),
                DropdownButton<String>(
                  value: _kind ?? 'all',
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'photo', child: Text('Photos')),
                    DropdownMenuItem(value: 'video', child: Text('Videos')),
                  ],
                  onChanged: (value) =>
                      setState(() => _kind = value == 'all' ? null : value),
                ),
              ],
            ),
          ),
          Expanded(
            child: NativeGallery(album: album, kind: _kind),
          ),
        ],
      ),
    );
  }
}

class _FolderCover extends ConsumerStatefulWidget {
  const _FolderCover({required this.album});
  final AlbumInfo album;
  @override
  ConsumerState<_FolderCover> createState() => _FolderCoverState();
}

class _FolderCoverState extends ConsumerState<_FolderCover> {
  late final Future<AssetInfo?> _cover = ref
      .read(mediaLibraryProvider)
      .photos({widget.album.id}, pageSize: 1)
      .first
      .then((items) => items.firstOrNull)
      .catchError((_) => null);
  @override
  Widget build(BuildContext context) => FutureBuilder<AssetInfo?>(
    future: _cover,
    builder: (context, snapshot) {
      final asset = snapshot.data;
      if (asset == null) {
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.folder_outlined),
        );
      }
      return FutureBuilder(
        future: ref
            .read(thumbnailServiceProvider)
            .get(asset.id, width: asset.width, height: asset.height),
        builder: (context, image) => image.data == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              )
            : Image.memory(image.data!, fit: BoxFit.cover),
      );
    },
  );
}
