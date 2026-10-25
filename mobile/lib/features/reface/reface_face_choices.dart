import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'reface_faces.dart';

class RefaceFaceChoices extends StatelessWidget {
  const RefaceFaceChoices({
    super.key,
    required this.groups,
    required this.selected,
    required this.onToggle,
    required this.keyPrefix,
    this.enabled = true,
  });
  final List<RefaceFaceGroup> groups;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final String keyPrefix;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < groups.length; i++)
        Semantics(
          selected: selected.contains(i),
          button: true,
          label: AppLocalizations.of(context).analyzeFaceTitle(i + 1),
          child: InkWell(
            key: Key('$keyPrefix-$i'),
            onTap: enabled ? () => onToggle(i) : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 100,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  width: selected.contains(i) ? 2 : 1,
                  color: selected.contains(i)
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: groups[i].representative.cropJpeg == null
                        ? const Icon(Icons.face_outlined, size: 48)
                        : Image.memory(
                            groups[i].representative.cropJpeg!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.face_outlined, size: 48),
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected.contains(i)
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text('${i + 1}'),
                    ],
                  ),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).refaceFaceAppearances(groups[i].appearances),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
