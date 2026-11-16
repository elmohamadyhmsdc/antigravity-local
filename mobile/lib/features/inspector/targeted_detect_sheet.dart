import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/api/dtos/analyze.dart';
import '../../ui/scaffolds/sheet_scaffold.dart';

/// Bottom sheet to choose target detection category and mode.
class TargetedDetectSheet extends StatefulWidget {
  const TargetedDetectSheet({super.key, required this.onStart, this.allowAnimeFaces = true});

  final bool allowAnimeFaces;

  final void Function(String kind, bool isRoiMode) onStart;

  static Future<void> show({
    required BuildContext context,
    required void Function(String kind, bool isRoiMode) onStart,
    bool allowAnimeFaces = true,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TargetedDetectSheet(onStart: onStart, allowAnimeFaces: allowAnimeFaces),
    );
  }

  @override
  State<TargetedDetectSheet> createState() => _TargetedDetectSheetState();
}

class _TargetedDetectSheetState extends State<TargetedDetectSheet> {
  String _selectedKind = 'area';
  bool _isRoiMode = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SheetScaffold(
      title: 'Targeted Detection',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select what you want to detect with high accuracy:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            // Kinds
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('target-kind-area'),
                  label: const Text('Exposed Areas'),
                  selected: _selectedKind == 'area',
                  onSelected: (val) => setState(() => _selectedKind = 'area'),
                ),
                ChoiceChip(
                  key: const Key('target-kind-body'),
                  label: const Text('Bodies (High Accuracy)'),
                  selected: _selectedKind == 'body',
                  onSelected: (val) => setState(() => _selectedKind = 'body'),
                ),
                ChoiceChip(
                  key: const Key('target-kind-face'),
                  label: const Text('Human faces'),
                  selected: _selectedKind == 'face',
                  onSelected: (val) => setState(() => _selectedKind = 'face'),
                ),
                if (widget.allowAnimeFaces)
                  ChoiceChip(
                    key: const Key('target-kind-anime-face'),
                    label: const Text('Anime face'),
                    selected: _selectedKind == 'anime_face',
                    onSelected: (_) => setState(() {
                      _selectedKind = 'anime_face';
                      _isRoiMode = true;
                    }),
                  ),
                ChoiceChip(
                  key: const Key('target-kind-object'),
                  label: const Text('Objects & Items'),
                  selected: _selectedKind == 'object',
                  onSelected: (val) => setState(() => _selectedKind = 'object'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mode
            if (_selectedKind == 'anime_face')
              const Text(
                'Draw a box around one anime face. Scan the area, then review and save. '
                'If detection misses it, you can confirm your box as a face.',
              ),
            if (_selectedKind != 'anime_face') ...[
              Text('Detection Scope:', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Full Photo', key: Key('target-mode-full')),
                    icon: Icon(Icons.fullscreen),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Draw Box (ROI)', key: Key('target-mode-roi')),
                    icon: Icon(Icons.crop),
                  ),
                ],
                selected: {_isRoiMode},
                onSelectionChanged: (set) =>
                    setState(() => _isRoiMode = set.first),
              ),
            ],
            const SizedBox(height: 24),

            FilledButton(
              key: const Key('target-start-detect'),
              onPressed: () async {
                final onStart = widget.onStart;
                final kind = _selectedKind;
                final roiMode = _isRoiMode;
                await Navigator.of(context).maybePop();
                onStart(kind, roiMode);
              },
              child: Text(_selectedKind == 'anime_face' ? 'Select face area' : 'Detect Now'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Naming and association dialog/sheet after detection or box placement.
class TargetedNameSheet extends StatefulWidget {
  const TargetedNameSheet({
    super.key,
    required this.kind,
    required this.bbox,
    this.initialName = '',
    this.cropJpeg,
    this.manual = false,
    this.isVideo = false,
    required this.onSave,
  });

  final String kind;
  final BBox bbox;
  final String initialName;
  final Uint8List? cropJpeg;
  final bool manual;
  final bool isVideo;
  final FutureOr<void> Function(String name, int? personId, String scope) onSave;

  static Future<void> show({
    required BuildContext context,
    required String kind,
    required BBox bbox,
    String initialName = '',
    Uint8List? cropJpeg,
    bool manual = false,
    bool isVideo = false,
    required FutureOr<void> Function(String name, int? personId, String scope) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TargetedNameSheet(
        kind: kind,
        bbox: bbox,
        initialName: initialName,
        cropJpeg: cropJpeg,
        manual: manual,
        isVideo: isVideo,
        onSave: onSave,
      ),
    );
  }

  @override
  State<TargetedNameSheet> createState() => _TargetedNameSheetState();
}

class _TargetedNameSheetState extends State<TargetedNameSheet> {
  late final TextEditingController _nameController;
  int? _personId;
  String _scope = 'single';
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SheetScaffold(
      title: widget.kind == 'anime_face' ? 'Confirm anime face' : 'Name & Save Detection',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.kind == 'anime_face') ...[
              if (widget.cropJpeg != null)
                SizedBox(
                  height: 140,
                  child: Image.memory(widget.cropJpeg!, fit: BoxFit.contain),
                ),
              const SizedBox(height: 12),
              Text(widget.manual
                  ? 'The detector missed this face. Saving confirms your selected box as an anime face.'
                  : 'Check the face crop before saving.'),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const Key('target-name-input'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: widget.kind == 'anime_face'
                    ? 'New character name (optional)'
                    : widget.kind == 'face'
                    ? 'Face name'
                    : widget.kind == 'area'
                    ? 'Area name (e.g. Chest, Arm, Tattoo)'
                    : widget.kind == 'body'
                    ? 'Body title or owner'
                    : 'Object / Item name',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),

            // Quick suggestion chips
            if (widget.kind == 'area')
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final suggestion in [
                    'Chest',
                    'Buttocks',
                    'Bikini',
                    'Tattoo',
                    'Back',
                  ])
                    ActionChip(
                      label: Text(suggestion),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _nameController.text = suggestion),
                    ),
                ],
              ),
            const SizedBox(height: 12),

            // Video ScopePicker
            if (widget.isVideo) ...[
              Text('Video Scope:', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                key: const Key('target-scope-picker'),
                segments: const [
                  ButtonSegment(
                    value: 'single',
                    label: Text('Frame', key: Key('scope-single')),
                  ),
                  ButtonSegment(
                    value: 'track',
                    label: Text('Track', key: Key('scope-track')),
                  ),
                  ButtonSegment(
                    value: 'wholeVideo',
                    label: Text('Video', key: Key('scope-video')),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (set) => setState(() => _scope = set.first),
              ),
              const SizedBox(height: 16),
            ],

            if (_saveError != null)
              Text(_saveError!, style: TextStyle(color: theme.colorScheme.error)),
            FilledButton(
              key: const Key('target-save'),
              onPressed: _saving ? null : () async {
                setState(() { _saving = true; _saveError = null; });
                try {
                  await widget.onSave(_nameController.text.trim(), _personId, _scope);
                  if (context.mounted) Navigator.of(context).maybePop();
                } catch (error) {
                  if (mounted) setState(() => _saveError = error.toString());
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
              child: Text(_saving ? 'Saving...' : 'Save & Apply'),
            ),
          ],
        ),
      ),
    );
  }
}
