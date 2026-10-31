import 'package:flutter/material.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../shared/crop_image.dart';

Future<List<int>?> pickActionFaces(
  BuildContext context, {
  required String title,
  required Future<List<FaceItem>> faces,
  bool single = false,
}) => showModalBottomSheet<List<int>>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _Picker(title: title, faces: faces, single: single),
);

class _Picker extends StatefulWidget {
  const _Picker({
    required this.title,
    required this.faces,
    required this.single,
  });
  final String title;
  final Future<List<FaceItem>> faces;
  final bool single;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final selected = <int>{};
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          ListTile(
            title: Text(widget.title),
            trailing: Text(l.selectedCount(selected.length)),
          ),
          Expanded(
            child: FutureBuilder<List<FaceItem>>(
              future: widget.faces,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(l.peopleActionError('${snapshot.error}')),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final faces = snapshot.data!;
                return Column(
                  children: [
                    if (!widget.single)
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () => setState(
                              () => selected.addAll(faces.map((f) => f.id)),
                            ),
                            child: Text(l.selectAll),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              final next = faces
                                  .map((f) => f.id)
                                  .where((id) => !selected.contains(id))
                                  .toSet();
                              selected
                                ..clear()
                                ..addAll(next);
                            }),
                            child: Text(l.peopleAction('invert')),
                          ),
                        ],
                      ),
                    if (faces.isEmpty)
                      Expanded(
                        child: Center(child: Text(l.peopleAction('noResults'))),
                      )
                    else
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 110,
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4,
                              ),
                          itemCount: faces.length,
                          itemBuilder: (context, i) {
                            final f = faces[i];
                            return Semantics(
                              button: true,
                              selected: selected.contains(f.id),
                              label: 'Face ${f.id}',
                              child: InkWell(
                                key: Key('action-pick-face-${f.id}'),
                                onTap: () {
                                  if (widget.single) {
                                    Navigator.pop(context, [f.id]);
                                    return;
                                  }
                                  setState(() {
                                    if (!selected.remove(f.id)) {
                                      selected.add(f.id);
                                    }
                                  });
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CropImage(path: f.cropPath),
                                    if (selected.contains(f.id))
                                      ColoredBox(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .35),
                                      ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Icon(
                                        selected.contains(f.id)
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (!widget.single)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, selected.toList()),
                  child: Text(l.peopleAction('done')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
