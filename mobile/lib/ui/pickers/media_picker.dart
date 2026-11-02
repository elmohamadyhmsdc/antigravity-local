import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/media_library.dart';
import '../../library_providers.dart';
import '../cards/entity_card.dart';
import '../collection/segmented_bar.dart';
import '../scaffolds/sheet_scaffold.dart';

/// L1/P5a — MediaPicker: Pick single or multiple photos/videos from Photos or Albums.
class MediaPicker extends ConsumerStatefulWidget {
  const MediaPicker({
    super.key,
    this.multiple = true,
    this.kind,
    this.title = 'Select media',
    this.initialSelectedIds = const {},
  });

  final bool multiple;
  final String? kind;
  final String title;
  final Set<String> initialSelectedIds;

  static Future<List<AssetInfo>?> pick(
    BuildContext context, {
    bool multiple = true,
    String? kind,
    String title = 'Select media',
    Set<String> initialSelectedIds = const {},
  }) {
    return SheetScaffold.show<List<AssetInfo>>(
      context: context,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: MediaPicker(
          multiple: multiple,
          kind: kind,
          title: title,
          initialSelectedIds: initialSelectedIds,
        ),
      ),
    );
  }

  @override
  ConsumerState<MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends ConsumerState<MediaPicker> {
  int _tab = 0;
  AlbumInfo? _selectedAlbum;
  final Set<String> _selectedIds = {};
  final Map<String, AssetInfo> _assetMap = {};
  List<AssetInfo> _assets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.initialSelectedIds);
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() => _loading = true);
    try {
      final library = ref.read(mediaLibraryProvider);
      final albumId = _selectedAlbum?.id ?? 'all';
      final stream = library.photos({albumId}, pageSize: 200);
      final firstBatch = await stream.first.catchError((_) => <AssetInfo>[]);
      if (mounted) {
        setState(() {
          _assets = widget.kind == null
              ? firstBatch
              : firstBatch.where((a) => a.kind == widget.kind).toList();
          for (final a in _assets) {
            _assetMap[a.id] = a;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onAssetTap(AssetInfo asset) {
    if (!widget.multiple) {
      Navigator.of(context).pop([asset]);
      return;
    }
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
      _assetMap[asset.id] = asset;
    });
  }

  void _onDone() {
    final result = _selectedIds
        .map((id) => _assetMap[id])
        .whereType<AssetInfo>()
        .toList();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(albumsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.title),
        leading: _selectedAlbum != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedAlbum = null;
                    _tab = 1;
                  });
                  _loadAssets();
                },
              )
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
        actions: [
          if (widget.multiple)
            FilledButton.tonal(
              key: const Key('media-picker-done'),
              onPressed: _selectedIds.isEmpty ? null : _onDone,
              child: Text(
                _selectedIds.isEmpty ? 'Done' : 'Done (${_selectedIds.length})',
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_selectedAlbum == null)
            SegmentedBar<int>(
              key: const Key('media-picker-tabs'),
              segments: const [
                SegmentItem(
                  value: 0,
                  label: 'Photos',
                  icon: Icons.photo_outlined,
                ),
                SegmentItem(
                  value: 1,
                  label: 'Albums',
                  icon: Icons.folder_outlined,
                ),
              ],
              selected: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
          if (_selectedAlbum != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedAlbum!.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedAlbum!.count} items',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Expanded(
            child: _selectedAlbum == null && _tab == 1
                ? albumsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Error: $err')),
                    data: (albums) {
                      final folders = albums.where((a) => !a.isAll).toList();
                      if (folders.isEmpty) {
                        return const Center(child: Text('No albums found'));
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.85,
                            ),
                        itemCount: folders.length,
                        itemBuilder: (context, index) {
                          final album = folders[index];
                          return EntityCard(
                            key: ValueKey('album-card-${album.id}'),
                            layout: EntityCardLayout.grid,
                            visual: const IconVisual(Icons.photo_library),
                            title: album.name,
                            subtitle: '${album.count} items',
                            onTap: () {
                              setState(() {
                                _selectedAlbum = album;
                                _tab = 0;
                              });
                              _loadAssets();
                            },
                          );
                        },
                      );
                    },
                  )
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : _assets.isEmpty
                ? const Center(child: Text('No media items'))
                : GridView.builder(
                    key: const Key('media-picker-grid'),
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      final isSelected = _selectedIds.contains(asset.id);
                      return InkWell(
                        key: ValueKey('picker-item-${asset.id}'),
                        onTap: () => _onAssetTap(asset),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FutureBuilder(
                              future: ref
                                  .read(thumbnailServiceProvider)
                                  .get(
                                    asset.id,
                                    width: asset.width,
                                    height: asset.height,
                                  ),
                              builder: (context, snapshot) =>
                                  snapshot.data == null
                                  ? ColoredBox(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: const Icon(Icons.photo_outlined),
                                    )
                                  : Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    ),
                            ),
                            if (widget.multiple)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : Colors.black38,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check,
                                          size: 16,
                                          color: theme.colorScheme.onPrimary,
                                        )
                                      : null,
                                ),
                              ),
                            if (asset.kind == 'video')
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
