import 'package:flutter/material.dart';
import '../../data/api/dtos/analyze.dart';
import '../../ui/scaffolds/sheet_scaffold.dart';

/// Bottom sheet to choose target detection category and mode.
class TargetedDetectSheet extends StatefulWidget {
  const TargetedDetectSheet({super.key, required this.onStart});

  final void Function(String kind, bool isRoiMode) onStart;

  static Future<void> show({
    required BuildContext context,
    required void Function(String kind, bool isRoiMode) onStart,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TargetedDetectSheet(onStart: onStart),
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
                  label: const Text('Faces (Native ROI)'),
                  selected: _selectedKind == 'face',
                  onSelected: (val) => setState(() => _selectedKind = 'face'),
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
            const SizedBox(height: 24),

            FilledButton(
              key: const Key('target-start-detect'),
              onPressed: () {
                Navigator.of(context).maybePop();
                widget.onStart(_selectedKind, _isRoiMode);
              },
              child: const Text('Detect Now'),
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
    this.isVideo = false,
    required this.onSave,
  });

  final String kind;
  final BBox bbox;
  final String initialName;
  final bool isVideo;
  final void Function(String name, int? personId, String scope) onSave;

  static Future<void> show({
    required BuildContext context,
    required String kind,
    required BBox bbox,
    String initialName = '',
    bool isVideo = false,
    required void Function(String name, int? personId, String scope) onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TargetedNameSheet(
        kind: kind,
        bbox: bbox,
        initialName: initialName,
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
      title: 'Name & Save Detection',
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
            TextField(
              key: const Key('target-name-input'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: widget.kind == 'area'
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

            FilledButton(
              key: const Key('target-save'),
              onPressed: () {
                Navigator.of(context).maybePop();
                widget.onSave(_nameController.text.trim(), _personId, _scope);
              },
              child: const Text('Save & Apply'),
            ),
          ],
        ),
      ),
    );
  }
}
