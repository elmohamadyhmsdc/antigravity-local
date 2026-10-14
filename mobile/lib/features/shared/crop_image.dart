import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';

/// A face or body crop from the phone's private crop store (relative path as kept in the database).
class CropImage extends ConsumerWidget {
  const CropImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth = 240,
    this.placeholderIcon = Icons.face_outlined,
  });

  final String? path;
  final BoxFit fit;
  final int cacheWidth;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(placeholderIcon, color: scheme.outline)),
    );
    final relative = path;
    if (relative == null || relative.isEmpty) return placeholder;
    return Image.file(
      ref.watch(fileStoreProvider).resolve(relative),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// Round cover of a person.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.cropPath, this.radius = 28});

  final String? cropPath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: CropImage(path: cropPath, cacheWidth: (radius * 6).round()),
      ),
    );
  }
}

/// "Sara", or "Person 12" for someone who was never named.
String personName(AppLocalizations l10n, PersonSummary person) =>
    person.isNamed ? person.name!.trim() : l10n.personFallbackName(person.id);

String personNameOf(
  AppLocalizations l10n,
  int id,
  Map<int, PersonSummary> people,
) {
  final p = people[id];
  return p == null ? l10n.personFallbackName(id) : personName(l10n, p);
}
