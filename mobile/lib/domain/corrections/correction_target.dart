sealed class CorrectionTarget {
  const CorrectionTarget();
}

class FaceLinkTarget extends CorrectionTarget {
  const FaceLinkTarget({
    required this.faceId,
    required this.mediaId,
    this.personId,
    this.trackId,
  });

  final int faceId;
  final int mediaId;
  final int? personId;
  final int? trackId;
}

class BodyLinkTarget extends CorrectionTarget {
  const BodyLinkTarget({
    required this.bodyId,
    required this.mediaId,
    this.personId,
    this.trackId,
    this.linkMethod,
  });

  final int bodyId;
  final int mediaId;
  final int? personId;
  final int? trackId;
  final String? linkMethod;
}

class BodyPairTarget extends CorrectionTarget {
  const BodyPairTarget({
    required this.bodyAId,
    required this.bodyBId,
    required this.mediaId,
  });

  final int bodyAId;
  final int bodyBId;
  final int mediaId;
}

class EquipmentOwnerTarget extends CorrectionTarget {
  const EquipmentOwnerTarget({
    required this.objectId,
    required this.mediaId,
    this.bodyId,
  });

  final int objectId;
  final int mediaId;
  final int? bodyId;
}

class SensitiveRegionTarget extends CorrectionTarget {
  const SensitiveRegionTarget({required this.regionId, required this.mediaId});

  final int regionId;
  final int mediaId;
}

class PoseMembershipTarget extends CorrectionTarget {
  const PoseMembershipTarget({
    required this.categoryId,
    required this.bodyId,
    this.isOutfit = false,
  });

  final int categoryId;
  final int bodyId;
  final bool isOutfit;
}

class PersonPairTarget extends CorrectionTarget {
  const PersonPairTarget({required this.personAId, required this.personBId});

  final int personAId;
  final int personBId;
}

class ActionSuggestionTarget extends CorrectionTarget {
  const ActionSuggestionTarget({required this.suggestionKey});

  final String suggestionKey;
}
