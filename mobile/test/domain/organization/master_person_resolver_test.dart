import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/organization/master_person_resolver.dart';

void main() {
  test('MasterPersonResolver selects organized person first, then largest face', () {
    const resolver = MasterPersonResolver();
    const p1 = PersonRow(id: 1, name: 'Ahmed', kind: 'person', createdAt: 0, hidden: false, favorite: false, pinned: false, groupingLocked: false);
    const p2 = PersonRow(id: 2, name: 'Sara', kind: 'person', createdAt: 0, hidden: false, favorite: false, pinned: false, groupingLocked: false);

    // Case 1: p1 is already organized into a folder, p2 is not
    final chosen1 = resolver.resolveMaster(
      candidates: [p1, p2],
      organizedPersonIds: {1},
    );
    expect(chosen1?.id, 1);

    // Case 2: Explicit choice overrides all
    final chosenExplicit = resolver.resolveMaster(
      candidates: [p1, p2],
      organizedPersonIds: {1},
      explicitChoice: 2,
    );
    expect(chosenExplicit?.id, 2);

    // Case 3: Neither or both organized -> largest bounding box area wins
    final chosen2 = resolver.resolveMasterByBbox(
      candidates: [p1, p2],
      faceBoxes: {
        1: [0.1, 0.1, 0.2, 0.2], // area = 0.04
        2: [0.4, 0.4, 0.4, 0.4], // area = 0.16
      },
    );
    expect(chosen2?.id, 2);
  });
}
