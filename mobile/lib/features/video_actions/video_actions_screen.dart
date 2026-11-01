import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/video_actions_repository.dart';
import '../../library_providers.dart';
import '../../l10n/app_localizations.dart';
import '../media/video_media_view.dart' show videoTime;
import '../reface/reface_video_trimmer.dart';
import '../shared/crop_image.dart' show personName;

class _MediaLabel extends ConsumerWidget {
  const _MediaLabel(this.media, {this.suffix = ''});
  final MediaRow media;
  final String suffix;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(mediaLocationProvider(media.assetId)).value;
    final label =
        location?.fileName ??
        '${media.kind == 'photo' ? 'Photo' : 'Video'} ${media.id}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: FutureBuilder<Uint8List?>(
            future: ref
                .read(mediaLibraryProvider)
                .thumbnail(
                  media.assetId,
                  width: media.width ?? 0,
                  height: media.height ?? 0,
                  size: 72,
                ),
            builder: (context, snapshot) => snapshot.data == null
                ? const Icon(Icons.photo_outlined)
                : Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text('$label$suffix', overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _MediaIdLabel extends ConsumerWidget {
  const _MediaIdLabel(this.id, {this.suffix = ''});
  final int id;
  final String suffix;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<MediaRow?>(
    future: ref.read(libraryRepositoryProvider).mediaById(id),
    builder: (context, snapshot) => snapshot.data == null
        ? Text('Media $id$suffix')
        : _MediaLabel(snapshot.data!, suffix: suffix),
  );
}

class VideoActionsScreen extends ConsumerWidget {
  const VideoActionsScreen({super.key, this.personId});
  final int? personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(videoActionsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Actions')),
      body: StreamBuilder<List<VideoAction>>(
        stream: repo.watchActions(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load actions'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final actions = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Name an activity in an analyzed photo or video, then compare other media. Suggestions are for you to review.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ActionExampleScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add an example'),
              ),
              if (actions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No actions yet. Choose a photo or video segment to create one.',
                  ),
                ),
              for (final action in actions)
                ListTile(
                  key: Key('action-${action.id}'),
                  leading: const Icon(Icons.motion_photos_on_outlined),
                  title: Text(action.name),
                  subtitle: Text(
                    '${action.examples.length} ${action.examples.length == 1 ? 'example' : 'examples'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoActionDetailScreen(
                        actionId: action.id,
                        personId: personId,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ActionExampleScreen extends ConsumerStatefulWidget {
  const ActionExampleScreen({super.key, this.media, this.actionId});
  final MediaRow? media;
  final String? actionId;
  @override
  ConsumerState<ActionExampleScreen> createState() =>
      _ActionExampleScreenState();
}

class _ActionExampleScreenState extends ConsumerState<ActionExampleScreen> {
  final _name = TextEditingController();
  late Future<List<MediaRow>> _mediaFuture;
  MediaRow? _media;
  File? _file;
  VideoTrimSelection? _range;
  List<ActionParticipant> _participants = [];
  final Set<int> _selected = {};
  String? _actionId, _error;
  bool _busy = false;
  bool _participantsLoaded = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(videoActionsRepositoryProvider);
    _mediaFuture = Future.wait([
      repo.analyzedPhotos(),
      repo.analyzedVideos(),
    ]).then((lists) => lists.expand((v) => v).toList());
    _actionId = widget.actionId;
    if (widget.media != null) _open(widget.media!);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _open(MediaRow media) async {
    setState(() {
      _media = media;
      _file = null;
      _range = null;
      _participants = [];
      _participantsLoaded = false;
      _selected.clear();
      _error = null;
    });
    if (media.kind == 'photo') return;
    try {
      final library = ref.read(mediaLibraryProvider);
      final file = library is VideoMediaLibrary
          ? await (library as VideoMediaLibrary).videoFile(media.assetId)
          : null;
      if (!mounted) return;
      setState(() {
        _file = file;
        if (file == null) {
          _error =
              'Original video unavailable. Restore access to choose a segment.';
        }
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not open the original video.');
      }
    }
  }

  Future<void> _findParticipants() async {
    final range = _range;
    if (_media == null || (_media!.kind == 'video' && range == null)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await ref
          .read(videoActionsRepositoryProvider)
          .participants(
            _media!.id,
            range?.start.inMilliseconds ?? 0,
            range?.end.inMilliseconds ?? 0,
          );
      if (mounted) {
        setState(() {
          _participants = found;
          _participantsLoaded = true;
          _selected.clear();
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final range = _range;
    if (_media == null || (_media!.kind == 'video' && range == null)) return;
    if (range != null &&
        range.end.inMilliseconds - range.start.inMilliseconds > 120000) {
      setState(() => _error = 'Choose a segment no longer than 2 minutes.');
      return;
    }
    if (_selected.isEmpty || _selected.length > 6) {
      setState(() => _error = 'Select between one and six participants.');
      return;
    }
    if (_actionId == null && _name.text.trim().isEmpty) {
      setState(() => _error = 'Name this action.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(videoActionsRepositoryProvider);
    String? createdId;
    try {
      final id = _actionId ?? await repo.saveAction(_name.text.trim());
      if (_actionId == null) createdId = id;
      if (_media!.kind == 'photo') {
        await repo.addPhotoExample(
          actionId: id,
          mediaId: _media!.id,
          participantIds: _selected.toList(),
        );
      } else {
        await repo.addExample(
          actionId: id,
          mediaId: _media!.id,
          startMs: range!.start.inMilliseconds,
          endMs: range.end.inMilliseconds,
          participantIds: _selected.toList(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (createdId != null) {
        try {
          await repo.deleteAction(createdId);
        } on Object {
          /* Preserve the original error. */
        }
      }
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(videoActionsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add action example')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose an analyzed photo or video. For video, mark a segment up to 2 minutes. Select the participants in the activity.',
          ),
          FutureBuilder<List<MediaRow>>(
            future: _mediaFuture,
            builder: (context, snapshot) {
              final videos = snapshot.data ?? const <MediaRow>[];
              if (snapshot.hasError) {
                return const Text('Could not load analyzed media.');
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: videos.any((v) => v.id == _media?.id)
                    ? _media?.id
                    : null,
                decoration: const InputDecoration(labelText: 'Analyzed media'),
                items: [
                  for (final video in videos)
                    DropdownMenuItem(
                      value: video.id,
                      child: _MediaLabel(
                        video,
                        suffix: video.kind == 'video'
                            ? ' · ${videoTime(video.durationMs ?? 0)}'
                            : '',
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) _open(videos.firstWhere((v) => v.id == id));
                },
              );
            },
          ),
          if (_media != null && _file != null)
            RefaceVideoTrimmer(
              key: ValueKey(_media!.id),
              file: _file!,
              enabled: !_busy,
              onChanged: (range) {
                setState(() {
                  _range = range;
                  _participants = [];
                  _participantsLoaded = false;
                  _selected.clear();
                });
              },
            ),
          if (_range != null || _media?.kind == 'photo')
            OutlinedButton(
              onPressed: _busy ? null : _findParticipants,
              child: const Text('Find participants'),
            ),
          if (_participantsLoaded && _participants.isEmpty)
            const Text(
              'No linked people with usable body poses found. Assign people and analyze this media again; older videos may need a rescan.',
            ),
          for (final participant in _participants)
            CheckboxListTile(
              value: _selected.contains(participant.id),
              title: Text(participant.name),
              onChanged: (value) => setState(() {
                if (value == true) {
                  _selected.add(participant.id);
                } else {
                  _selected.remove(participant.id);
                }
              }),
            ),
          if (widget.actionId == null)
            StreamBuilder<List<VideoAction>>(
              stream: repo.watchActions(),
              builder: (context, snapshot) => Column(
                children: [
                  if ((snapshot.data ?? const <VideoAction>[]).isNotEmpty)
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: _actionId,
                      decoration: const InputDecoration(labelText: 'Action'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Create a new action'),
                        ),
                        for (final action in snapshot.data!)
                          DropdownMenuItem(
                            value: action.id,
                            child: Text(action.name),
                          ),
                      ],
                      onChanged: (id) => setState(() => _actionId = id),
                    ),
                  if (_actionId == null)
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'New action name',
                      ),
                    ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed:
                _busy ||
                    _media == null ||
                    (_media!.kind == 'video' && _range == null)
                ? null
                : _save,
            child: const Text('Save example'),
          ),
        ],
      ),
    );
  }
}

class VideoActionDetailScreen extends ConsumerStatefulWidget {
  const VideoActionDetailScreen({
    super.key,
    required this.actionId,
    this.personId,
  });
  final String actionId;
  final int? personId;
  @override
  ConsumerState<VideoActionDetailScreen> createState() =>
      _VideoActionDetailScreenState();
}

class _VideoActionDetailScreenState
    extends ConsumerState<VideoActionDetailScreen> {
  late Future<List<MediaRow>> _mediaFuture;
  int? _videoId, _personId;
  String _state = 'all';
  String _kind = 'all';
  bool _busy = false, _mirror = false;
  double _threshold = .82;
  String? _error;

  @override
  void initState() {
    super.initState();
    _personId = widget.personId;
    final repo = ref.read(videoActionsRepositoryProvider);
    _mediaFuture = Future.wait([
      repo.analyzedPhotos(),
      repo.analyzedVideos(),
    ]).then((lists) => lists.expand((v) => v).toList());
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(videoActionsRepositoryProvider)
          .search(
            widget.actionId,
            mediaIds: _videoId == null ? null : {_videoId!},
            minSimilarity: _threshold,
            allowMirror: _mirror,
          );
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(VideoActionMatch match, bool accepted) async {
    try {
      await ref
          .read(videoActionsRepositoryProvider)
          .reviewMatch(widget.actionId, match.id, accepted: accepted);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(videoActionsRepositoryProvider);
    return StreamBuilder<List<VideoAction>>(
      stream: repo.watchActions(),
      builder: (context, actions) {
        if (actions.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Action')),
            body: const Center(child: Text('Could not load this action.')),
          );
        }
        if (!actions.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Action')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final action = (actions.data ?? const <VideoAction>[])
            .where((a) => a.id == widget.actionId)
            .firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: Text(action?.name ?? 'Video action'),
            actions: [
              if (action != null)
                IconButton(
                  tooltip: 'Delete action',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete this action?'),
                        content: const Text(
                          'Its examples and reviews will be removed. Original videos remain.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await repo.deleteAction(widget.actionId);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
            ],
          ),
          body: action == null
              ? const Center(child: Text('Action unavailable'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Examples',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Examples describe activity in media, not a person.',
                    ),
                    for (final example in action.examples)
                      ListTile(
                        title: _MediaIdLabel(
                          example.mediaId,
                          suffix: example.kind == 'video'
                              ? ' · ${videoTime(example.startMs)}–${videoTime(example.endMs)}'
                              : '',
                        ),
                        subtitle: Text(
                          '${example.kind == 'video' ? '${example.frameCount} sampled frames · ' : ''}${example.participantIds.length} ${example.participantIds.length == 1 ? 'participant' : 'participants'}',
                        ),
                        onTap: () => context.push(
                          '${Routes.media}/${example.mediaId}?at=${example.startMs}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove example',
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await repo.removeExample(action.id, example.id);
                          },
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ActionExampleScreen(actionId: action.id),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add example'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Find similar activities',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Similarity ranks photo configurations or video motion against your examples; it is not a probability. Review each suggestion.',
                    ),
                    FutureBuilder<List<MediaRow>>(
                      future: _mediaFuture,
                      builder: (context, snapshot) =>
                          DropdownButtonFormField<int?>(
                            isExpanded: true,
                            initialValue: _videoId,
                            decoration: const InputDecoration(
                              labelText: 'Media',
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('All analyzed media'),
                              ),
                              for (final video
                                  in snapshot.data ?? const <MediaRow>[])
                                DropdownMenuItem(
                                  value: video.id,
                                  child: _MediaLabel(video),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _videoId = value),
                          ),
                    ),
                    SwitchListTile(
                      title: const Text('Allow mirrored motion'),
                      value: _mirror,
                      onChanged: (value) => setState(() => _mirror = value),
                    ),
                    Text('Minimum similarity ${(_threshold * 100).round()}%'),
                    Slider(
                      value: _threshold,
                      min: .5,
                      max: 1,
                      divisions: 50,
                      onChanged: (value) => setState(() => _threshold = value),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _search,
                      icon: const Icon(Icons.search),
                      label: Text(_busy ? 'Searching…' : 'Find suggestions'),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'Matches',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _state,
                      decoration: const InputDecoration(
                        labelText: 'Review status',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(
                          value: 'suggested',
                          child: Text('Suggested'),
                        ),
                        DropdownMenuItem(
                          value: 'confirmed',
                          child: Text('Accepted'),
                        ),
                        DropdownMenuItem(
                          value: 'rejected',
                          child: Text('Rejected'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _state = value ?? 'all'),
                    ),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _kind,
                      decoration: const InputDecoration(
                        labelText: 'Media type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Photos and videos'),
                        ),
                        DropdownMenuItem(value: 'photo', child: Text('Photos')),
                        DropdownMenuItem(value: 'video', child: Text('Videos')),
                      ],
                      onChanged: (value) =>
                          setState(() => _kind = value ?? 'all'),
                    ),
                    StreamBuilder<List<VideoActionMatch>>(
                      stream: repo.watchMatches(action.id),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text('Could not load matches.');
                        }
                        if (!snapshot.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final people = <int>{
                          ?_personId,
                          for (final match in snapshot.data!)
                            ...match.participantIds,
                        };
                        final matches = snapshot.data!
                            .where(
                              (m) =>
                                  (_state == 'all' || m.state == _state) &&
                                  (_kind == 'all' || m.kind == _kind) &&
                                  (_videoId == null || m.mediaId == _videoId) &&
                                  (_personId == null ||
                                      m.participantIds.contains(_personId)),
                            )
                            .toList();
                        return Column(
                          children: [
                            DropdownButtonFormField<int?>(
                              isExpanded: true,
                              initialValue: people.contains(_personId)
                                  ? _personId
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Participant',
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('All participants'),
                                ),
                                for (final id in people)
                                  DropdownMenuItem(
                                    value: id,
                                    child: Text(() {
                                      final person =
                                          (ref.watch(peopleProvider).value ??
                                                  const [])
                                              .where((p) => p.id == id)
                                              .firstOrNull;
                                      return person == null
                                          ? 'Person $id'
                                          : personName(
                                              AppLocalizations.of(context),
                                              person,
                                            );
                                    }()),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _personId = value),
                            ),
                            if (matches.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No matches for these filters.'),
                              ),
                            for (final match in matches)
                              Card(
                                child: Column(
                                  children: [
                                    ListTile(
                                      title: _MediaIdLabel(
                                        match.mediaId,
                                        suffix: match.kind == 'video'
                                            ? ' · ${videoTime(match.startMs)}–${videoTime(match.endMs)}'
                                            : '',
                                      ),
                                      subtitle: Text(
                                        '${(match.similarity * 100).round()}% ${match.kind == 'photo' ? 'configuration' : 'motion'} similarity · ${match.state} · ${match.participantIds.length} ${match.participantIds.length == 1 ? 'participant' : 'participants'}',
                                      ),
                                      trailing: Icon(
                                        match.kind == 'photo'
                                            ? Icons.photo_outlined
                                            : Icons.play_circle_outline,
                                      ),
                                      onTap: () => context.push(
                                        '${Routes.media}/${match.mediaId}?at=${match.startMs}',
                                      ),
                                    ),
                                    if (match.state == 'suggested')
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () =>
                                                _review(match, false),
                                            child: const Text('Reject'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _review(match, true),
                                            child: const Text('Accept'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
        );
      },
    );
  }
}
