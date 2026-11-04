import '../../data/repositories/media_queries.dart';
import '../../domain/actions/action_id.dart';

/// Only expose actions implemented by the media viewer for this detection.
Set<ActionId> detectionActionsFor(MediaDetection detection) => {
  ActionId.notARealThing,
  if (detection.isFace || detection.isBody) ...{
    ActionId.assignPerson,
    ActionId.changeKind,
    ActionId.refaceThis,
    if (detection.personId != null) ...{ActionId.open, ActionId.notThisPerson},
  },
  if (detection.isFace) ActionId.delete,
  if (detection.isBody) ...{
    ActionId.restyleThis,
    ActionId.similarPose,
    ActionId.similarColours,
    ActionId.namePose,
    ActionId.nameOutfit,
    ActionId.nameGroupPose,
    ActionId.markTattoo,
    ActionId.boxEquipment,
  },
};
