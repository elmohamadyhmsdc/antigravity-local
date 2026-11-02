enum CorrectionVerb {
  reassign,
  notThisPerson,
  belongsToNoOne,
  notARealThing,
  notSamePerson,
  unlink,
  confirm;

  String get labelEn => switch (this) {
    reassign => 'Move to another person...',
    notThisPerson => 'Not this person',
    belongsToNoOne => 'Belongs to no one',
    notARealThing => 'Not a real thing',
    notSamePerson => 'Not the same person',
    unlink => 'Unlink (reset to auto)',
    confirm => 'Confirm link',
  };
}
