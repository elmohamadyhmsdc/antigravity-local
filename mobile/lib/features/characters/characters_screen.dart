import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/character_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';

final _samplesProvider = StreamProvider.autoDispose
    .family<List<CharacterSampleRow>, int>(
      (ref, id) => ref.watch(characterRepositoryProvider).watchSamples(id),
    );

class CharactersScreen extends ConsumerWidget {
  const CharactersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final characters = ref.watch(charactersProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.charactersTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('test-character-photo'),
            tooltip: l.charactersTestPhoto,
            onPressed: () => context.push('${Routes.analyze}?characters=true'),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: characters.when(
        loading: () => const LoadingBox(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '$e',
          actionLabel: l.retry,
          onAction: () => ref.invalidate(charactersProvider),
        ),
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: l.charactersEmpty,
                body: l.charactersEmptyHint,
                actionLabel: l.scanLibrary,
                onAction: () => context.push(Routes.sources),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(l.charactersAccuracyHint),
                  const SizedBox(height: 16),
                  for (final c in items) _CharacterGroup(character: c),
                ],
              ),
      ),
    );
  }
}

class _CharacterGroup extends ConsumerWidget {
  const _CharacterGroup({required this.character});
  final CharacterSummary character;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(characterRepositoryProvider);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _CharacterNameDialog(name: character.name),
    );
    if (value != null) await repository.rename(character.id, value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Card(
      child: ExpansionTile(
        key: PageStorageKey('character-${character.id}'),
        leading: SizedBox(
          width: 48,
          height: 64,
          child: CropImage(path: character.cropPath, fit: BoxFit.contain),
        ),
        title: Text(character.name ?? l.characterFallback(character.id)),
        subtitle: Text(l.characterSamples(character.samples)),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => _rename(context, ref),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.rename),
            ),
          ),
          _CharacterSamples(id: character.id),
        ],
      ),
    );
  }
}

class _CharacterNameDialog extends StatefulWidget {
  const _CharacterNameDialog({this.name});
  final String? name;
  @override
  State<_CharacterNameDialog> createState() => _CharacterNameDialogState();
}

class _CharacterNameDialogState extends State<_CharacterNameDialog> {
  late final _field = TextEditingController(text: widget.name ?? '');
  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.characterName),
      content: TextField(
        controller: _field,
        maxLength: 80,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _field.text),
          child: Text(l.save),
        ),
      ],
    );
  }
}

class _CharacterSamples extends ConsumerStatefulWidget {
  const _CharacterSamples({required this.id});
  final int id;
  @override
  ConsumerState<_CharacterSamples> createState() => _CharacterSamplesState();
}

class _CharacterSamplesState extends ConsumerState<_CharacterSamples> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ref
        .watch(_samplesProvider(widget.id))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (samples) {
            final pages = (samples.length / 24).ceil().clamp(1, 1 << 30);
            final page = _page.clamp(0, pages - 1);
            return Column(
              children: [
                for (final s in samples.skip(page * 24).take(24))
                  ListTile(
                    leading: SizedBox(
                      width: 64,
                      height: 72,
                      child: CropImage(path: s.cropPath, fit: BoxFit.contain),
                    ),
                    title: Text(
                      s.timestampMs == null
                          ? l.characterOpenSource
                          : '${Duration(milliseconds: s.timestampMs!)}'
                                .split('.')
                                .first,
                    ),
                    onTap: () => context.push('${Routes.media}/${s.mediaId}'),
                    trailing: samples.length < 2
                        ? null
                        : IconButton(
                            tooltip: l.characterSeparate,
                            icon: const Icon(Icons.call_split),
                            onPressed: () => ref
                                .read(characterRepositoryProvider)
                                .separate(s.id),
                          ),
                  ),
                if (pages > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: page == 0
                            ? null
                            : () => setState(() => _page = page - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('${page + 1} / $pages'),
                      IconButton(
                        onPressed: page + 1 >= pages
                            ? null
                            : () => setState(() => _page = page + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            );
          },
        );
  }
}
