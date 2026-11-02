import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/ui/selection/selection_controller.dart';

void main() {
  test('SelectionController handles toggle, selectAll, and clear', () {
    final controller = SelectionController<String>(idExtractor: (item) => item);

    expect(controller.isSelecting, isFalse);
    expect(controller.count, equals(0));

    controller.toggle('a');
    expect(controller.isSelecting, isTrue);
    expect(controller.count, equals(1));
    expect(controller.isSelected('a'), isTrue);

    controller.toggle('b');
    expect(controller.count, equals(2));

    controller.toggle('a');
    expect(controller.count, equals(1));
    expect(controller.isSelected('a'), isFalse);

    controller.selectAll(['x', 'y', 'z']);
    expect(controller.count, equals(4)); // b + x + y + z

    controller.clear();
    expect(controller.isSelecting, isFalse);
    expect(controller.count, equals(0));
  });
}
