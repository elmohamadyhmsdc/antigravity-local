import 'package:flutter/material.dart';

import '../../features/shared/person_picker.dart' as legacy;

export '../../features/shared/person_picker.dart' show PersonChoice;

class PersonPicker {
  PersonPicker._();

  static Future<legacy.PersonChoice?> show(
    BuildContext context, {
    int? excludePersonId,
    String? title,
    bool allowNew = true,
    String kind = 'person',
  }) {
    return legacy.pickPerson(
      context,
      excludePersonId: excludePersonId,
      title: title,
      allowNew: allowNew,
      kind: kind,
    );
  }
}
