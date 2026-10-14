import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/media_queries.dart';
import '../../library_providers.dart';
import '../shared/empty_state.dart';

/// A paged grid of the user's photos. Rows come from the database a page at a time (a library can
/// hold 100k photos) and thumbnails from MediaStore; it refreshes itself while a scan adds photos.
class MediaGrid extends ConsumerStatefulWidget {
  const MediaGrid({
    super.key,
    required this.filter,
    required this.empty,
    this.columns = 3,
  });

  final MediaFilter filter;
  final Widget empty;
  final int columns;

  @override
  ConsumerState<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends ConsumerState<MediaGrid> {
  static const _pageSize = 90;

  int? _count;
  final _pages = <int, Future<List<MediaListItem>>>{};
  StreamSubscription<void>? _changes;
  Timer? _debounce;

  MediaQueries get _queries => ref.read(mediaQueriesProvider);

  @override
  void initState() {
    super.initState();
    _reload();
    _changes = _queries.changes().listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _reload);
    });
  }

  @override
  void didUpdateWidget(MediaGrid old) {
    super.didUpdateWidget(old);
    if (old.filter != widget.filter) _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final count = await _queries.count(widget.filter);
    if (!mounted) return;
    setState(() {
      _count = count;
      _pages.clear();
    });
  }

  Future<List<MediaListItem>> _page(int page) => _pages.putIfAbsent(
    page,
    () => _queries.page(
      widget.filter,
      offset: page * _pageSize,
      limit: _pageSize,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final count = _count;
    if (count == null) return const LoadingBox();
    if (count == 0) return widget.empty;
    return GridView.builder(
      key: const Key('media-grid'),
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columns,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: count,
      itemBuilder: (context, index) => FutureBuilder<List<MediaListItem>>(
        future: _page(index ~/ _pageSize),
        builder: (context, snapshot) {
          final items = snapshot.data;
          final at = index % _pageSize;
          if (items == null || at >= items.length) {
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            );
          }
          return MediaTile(item: items[at]);
        },
      ),
    );
  }
}

/// One photo in a grid: thumbnail, how many faces were found, whether it is scanned yet.
class MediaTile extends ConsumerWidget {
  const MediaTile({super.key, required this.item});

  final MediaListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final thumbs = ref.watch(thumbnailServiceProvider);
    return GestureDetector(
      key: Key('media-${item.id}'),
      onTap: () => context.push('${Routes.media}/${item.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder(
            future: thumbs.get(
              item.assetId,
              width: item.width,
              height: item.height,
            ),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    snapshot.connectionState == ConnectionState.done
                        ? Icons.broken_image_outlined
                        : Icons.photo_outlined,
                    color: scheme.outline,
                  ),
                );
              }
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            },
          ),
          if (item.faceCount > 0)
            Positioned(
              left: 4,
              bottom: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.face, size: 12, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(
                        '${item.faceCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (item.scanStatus == 'failed')
            const Positioned(
              right: 4,
              top: 4,
              child: Icon(Icons.error, size: 18, color: Colors.redAccent),
            )
          else if (item.scanStatus != 'done')
            const Positioned(
              right: 4,
              top: 4,
              child: Icon(
                Icons.hourglass_empty,
                size: 16,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }
}
