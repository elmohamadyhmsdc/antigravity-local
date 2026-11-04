import '../../data/db/app_database.dart';

class MasterPersonResolver {
  const MasterPersonResolver();

  /// Resolves the primary/master person for a media item.
  /// 1. An explicit choice (e.g. from user or prior organization) always wins.
  /// 2. If candidates contain persons who already have organized folders, those take priority.
  /// 3. Otherwise, returns the first candidate or null if empty.
  PersonRow? resolveMaster({
    required List<PersonRow> candidates,
    Set<int> organizedPersonIds = const {},
    int? explicitChoice,
  }) {
    if (candidates.isEmpty) return null;
    if (explicitChoice != null) {
      final chosen = candidates
          .where((p) => p.id == explicitChoice)
          .firstOrNull;
      if (chosen != null) return chosen;
    }

    final organized = candidates
        .where((p) => organizedPersonIds.contains(p.id))
        .toList();
    if (organized.isNotEmpty) {
      return organized.first;
    }

    return candidates.first;
  }

  /// Resolves master by facial area/prominence (bbox = [x, y, w, h]).
  PersonRow? resolveMasterByBbox({
    required List<PersonRow> candidates,
    required Map<int, List<double>> faceBoxes,
    int? explicitChoice,
  }) {
    if (candidates.isEmpty) return null;
    if (explicitChoice != null) {
      final chosen = candidates
          .where((p) => p.id == explicitChoice)
          .firstOrNull;
      if (chosen != null) return chosen;
    }

    PersonRow? bestPerson;
    var bestArea = -1.0;

    for (final person in candidates) {
      final box = faceBoxes[person.id];
      if (box != null && box.length >= 4) {
        final area = box[2] * box[3];
        if (area > bestArea) {
          bestArea = area;
          bestPerson = person;
        }
      }
    }

    return bestPerson ?? candidates.first;
  }
}
