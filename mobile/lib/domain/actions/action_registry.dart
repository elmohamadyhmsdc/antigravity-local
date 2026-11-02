import 'package:flutter/material.dart';

import 'action_context.dart';
import 'action_id.dart';
import 'entity_ref.dart';

class ActionSpec {
  const ActionSpec({
    required this.id,
    required this.icon,
    required this.labelKey,
    required this.labelEn,
    required this.isAvailable,
    this.isDanger = false,
  });

  final ActionId id;
  final IconData icon;
  final String labelKey;
  final String labelEn;
  final bool Function(EntityRef entity, ActionContext context) isAvailable;
  final bool isDanger;

  ActionGroup get group => id.group;
}

class ActionRegistry {
  ActionRegistry._();

  static final Map<ActionId, ActionSpec> _specs = {
    // -------------------------------------------------------------
    // عرض (View)
    // -------------------------------------------------------------
    ActionId.open: ActionSpec(
      id: ActionId.open,
      icon: Icons.open_in_new,
      labelKey: 'actionOpen',
      labelEn: 'Open',
      isAvailable: (entity, ctx) => true,
    ),
    ActionId.info: ActionSpec(
      id: ActionId.info,
      icon: Icons.info_outline,
      labelKey: 'actionDetails',
      labelEn: 'Details',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef ||
          entity is FaceEntityRef ||
          entity is BodyEntityRef ||
          entity is ActionEntityRef ||
          entity is ResultEntityRef ||
          entity is JobEntityRef ||
          entity is ModelEntityRef ||
          entity is DatasetEntityRef,
    ),
    ActionId.expand: ActionSpec(
      id: ActionId.expand,
      icon: Icons.fullscreen,
      labelKey: 'actionExpand',
      labelEn: 'Expand / Lens',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef ||
          entity is FaceEntityRef ||
          entity is BodyEntityRef ||
          entity is PersonEntityRef ||
          entity is ClusterEntityRef ||
          entity is ResultEntityRef,
    ),
    ActionId.openPhoto: ActionSpec(
      id: ActionId.openPhoto,
      icon: Icons.photo_outlined,
      labelKey: 'actionOpenOriginal',
      labelEn: 'Open original',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef ||
          entity is BodyEntityRef ||
          entity is ActionEntityRef ||
          (entity is ResultEntityRef && entity.sourceMediaId != null),
    ),
    ActionId.openNativePlayer: ActionSpec(
      id: ActionId.openNativePlayer,
      icon: Icons.play_circle_outline,
      labelKey: 'actionOpenInPlayer',
      labelEn: 'Open in player',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef && (entity.isVideo || ctx.isVideo),
    ),

    // -------------------------------------------------------------
    // تعريف (Identity / Linking)
    // -------------------------------------------------------------
    ActionId.rename: ActionSpec(
      id: ActionId.rename,
      icon: Icons.edit_outlined,
      labelKey: 'actionRename',
      labelEn: 'Rename',
      isAvailable: (entity, ctx) =>
          entity is PersonEntityRef ||
          entity is GroupEntityRef ||
          entity is ActionEntityRef ||
          entity is ClusterEntityRef ||
          entity is ModelEntityRef ||
          entity is DatasetEntityRef,
    ),
    ActionId.assignPerson: ActionSpec(
      id: ActionId.assignPerson,
      icon: Icons.person_add_outlined,
      labelKey: 'actionAssignPerson',
      labelEn: 'Assign to person',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef ||
          entity is BodyEntityRef ||
          (entity is ClusterEntityRef &&
              (entity.kind == ClusterKind.mark ||
                  entity.kind == ClusterKind.equipment)),
    ),
    ActionId.setCover: ActionSpec(
      id: ActionId.setCover,
      icon: Icons.star_outline,
      labelKey: 'actionSetCover',
      labelEn: 'Set as cover',
      isAvailable: (entity, ctx) => entity is FaceEntityRef,
    ),
    ActionId.moveToGroup: ActionSpec(
      id: ActionId.moveToGroup,
      icon: Icons.folder_outlined,
      labelKey: 'actionMoveToGroup',
      labelEn: 'Move to group',
      isAvailable: (entity, ctx) => entity is PersonEntityRef,
    ),
    ActionId.markTattoo: ActionSpec(
      id: ActionId.markTattoo,
      icon: Icons.draw_outlined,
      labelKey: 'actionMarkTattoo',
      labelEn: 'Mark tattoo',
      isAvailable: (entity, ctx) => entity is BodyEntityRef,
    ),
    ActionId.confirmLink: ActionSpec(
      id: ActionId.confirmLink,
      icon: Icons.check_circle_outline,
      labelKey: 'actionConfirmLink',
      labelEn: 'Confirm link',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef || entity is BodyEntityRef,
    ),
    ActionId.unlink: ActionSpec(
      id: ActionId.unlink,
      icon: Icons.link_off,
      labelKey: 'actionUnlink',
      labelEn: 'Unlink',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef || entity is BodyEntityRef,
    ),
    ActionId.notThisPerson: ActionSpec(
      id: ActionId.notThisPerson,
      icon: Icons.person_remove_outlined,
      labelKey: 'actionNotThisPerson',
      labelEn: 'Not this person',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef ||
          (entity is BodyEntityRef &&
              (entity.personId != null || ctx.hasPerson)),
    ),
    ActionId.belongsToNoOne: ActionSpec(
      id: ActionId.belongsToNoOne,
      icon: Icons.person_off_outlined,
      labelKey: 'actionBelongsToNoOne',
      labelEn: 'Belongs to no one',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef || entity is BodyEntityRef,
    ),
    ActionId.notARealThing: ActionSpec(
      id: ActionId.notARealThing,
      icon: Icons.visibility_off_outlined,
      labelKey: 'actionNotARealDetection',
      labelEn: 'Not a real detection',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef ||
          entity is BodyEntityRef ||
          entity is EquipmentEntityRef,
    ),
    ActionId.notSamePerson: ActionSpec(
      id: ActionId.notSamePerson,
      icon: Icons.call_split,
      labelKey: 'actionNotSamePerson',
      labelEn: 'Not same person',
      isAvailable: (entity, ctx) =>
          entity is PersonEntityRef ||
          (entity is BodyEntityRef && (entity.trackId != null || ctx.isVideo)),
    ),
    ActionId.changeKind: ActionSpec(
      id: ActionId.changeKind,
      icon: Icons.swap_horiz,
      labelKey: 'actionChangeFigureKind',
      labelEn: 'Change figure kind',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef || entity is BodyEntityRef,
    ),
    ActionId.changeFileKind: ActionSpec(
      id: ActionId.changeFileKind,
      icon: Icons.tune,
      labelKey: 'actionChangeFileKind',
      labelEn: 'Change file kind',
      isAvailable: (entity, ctx) => entity is MediaEntityRef,
    ),
    ActionId.setSensitivity: ActionSpec(
      id: ActionId.setSensitivity,
      icon: Icons.shield_outlined,
      labelKey: 'actionSetSensitive',
      labelEn: 'Set sensitive',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef || entity is SensitiveRegionEntityRef,
    ),
    ActionId.addEquipment: ActionSpec(
      id: ActionId.addEquipment,
      icon: Icons.handyman_outlined,
      labelKey: 'actionAddEquipment',
      labelEn: 'Add equipment',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef || entity is EquipmentEntityRef,
    ),
    ActionId.boxEquipment: ActionSpec(
      id: ActionId.boxEquipment,
      icon: Icons.crop_free,
      labelKey: 'actionEquipmentBox',
      labelEn: 'Equipment box',
      isAvailable: (entity, ctx) => entity is EquipmentEntityRef,
    ),
    ActionId.namePose: ActionSpec(
      id: ActionId.namePose,
      icon: Icons.accessibility_new,
      labelKey: 'actionNamePose',
      labelEn: 'Name pose',
      isAvailable: (entity, ctx) => entity is BodyEntityRef,
    ),
    ActionId.nameOutfit: ActionSpec(
      id: ActionId.nameOutfit,
      icon: Icons.checkroom,
      labelKey: 'actionNameOutfit',
      labelEn: 'Name outfit',
      isAvailable: (entity, ctx) => entity is BodyEntityRef,
    ),
    ActionId.nameGroupPose: ActionSpec(
      id: ActionId.nameGroupPose,
      icon: Icons.groups,
      labelKey: 'actionNameGroupPose',
      labelEn: 'Name group pose',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef || entity is BodyEntityRef,
    ),

    // -------------------------------------------------------------
    // بحث (Search)
    // -------------------------------------------------------------
    ActionId.similarPose: ActionSpec(
      id: ActionId.similarPose,
      icon: Icons.accessibility_new,
      labelKey: 'actionSimilarPose',
      labelEn: 'Similar pose',
      isAvailable: (entity, ctx) => entity is BodyEntityRef,
    ),
    ActionId.similarColours: ActionSpec(
      id: ActionId.similarColours,
      icon: Icons.palette_outlined,
      labelKey: 'actionSimilarColours',
      labelEn: 'Similar colours',
      isAvailable: (entity, ctx) => entity is BodyEntityRef,
    ),
    ActionId.similarFaces: ActionSpec(
      id: ActionId.similarFaces,
      icon: Icons.face,
      labelKey: 'actionSimilarFaces',
      labelEn: 'Similar faces',
      isAvailable: (entity, ctx) => entity is FaceEntityRef,
    ),
    ActionId.personMedia: ActionSpec(
      id: ActionId.personMedia,
      icon: Icons.photo_library_outlined,
      labelKey: 'actionPersonMedia',
      labelEn: 'Person media',
      isAvailable: (entity, ctx) => entity is PersonEntityRef,
    ),

    // -------------------------------------------------------------
    // إنشاء (Create / Studio)
    // -------------------------------------------------------------
    ActionId.refaceThis: ActionSpec(
      id: ActionId.refaceThis,
      icon: Icons.face_retouching_natural,
      labelKey: 'actionRefaceTarget',
      labelEn: 'Reface target',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef ||
          entity is FaceEntityRef ||
          entity is BodyEntityRef,
    ),
    ActionId.refaceWith: ActionSpec(
      id: ActionId.refaceWith,
      icon: Icons.face_retouching_natural,
      labelKey: 'actionRefaceWithIdentity',
      labelEn: 'Reface with identity',
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef ||
          (entity is PersonEntityRef &&
              !entity.isCharacter &&
              !ctx.isCharacter),
    ),
    ActionId.restyleThis: ActionSpec(
      id: ActionId.restyleThis,
      icon: Icons.auto_fix_high,
      labelKey: 'actionRestyleBody',
      labelEn: 'Restyle body',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef || entity is BodyEntityRef,
    ),
    ActionId.generateWith: ActionSpec(
      id: ActionId.generateWith,
      icon: Icons.auto_awesome,
      labelKey: 'actionGenerateWithModel',
      labelEn: 'Generate with model',
      isAvailable: (entity, ctx) =>
          entity is ModelEntityRef || entity is PersonEntityRef,
    ),
    ActionId.addToDataset: ActionSpec(
      id: ActionId.addToDataset,
      icon: Icons.add_photo_alternate_outlined,
      labelKey: 'actionAddToDataset',
      labelEn: 'Add to dataset',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef ||
          entity is FaceEntityRef ||
          entity is PersonEntityRef,
    ),
    ActionId.trainModel: ActionSpec(
      id: ActionId.trainModel,
      icon: Icons.model_training,
      labelKey: 'actionTrainModel',
      labelEn: 'Train model',
      isAvailable: (entity, ctx) =>
          (entity is PersonEntityRef &&
              !entity.isCharacter &&
              !ctx.isCharacter) ||
          entity is DatasetEntityRef,
    ),
    ActionId.runAgain: ActionSpec(
      id: ActionId.runAgain,
      icon: Icons.replay,
      labelKey: 'actionRunAgain',
      labelEn: 'Run again',
      isAvailable: (entity, ctx) =>
          entity is ResultEntityRef || entity is JobEntityRef,
    ),

    // -------------------------------------------------------------
    // إدارة (Manage)
    // -------------------------------------------------------------
    ActionId.share: ActionSpec(
      id: ActionId.share,
      icon: Icons.share_outlined,
      labelKey: 'actionShare',
      labelEn: 'Share',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef || entity is ResultEntityRef,
    ),
    ActionId.saveToGallery: ActionSpec(
      id: ActionId.saveToGallery,
      icon: Icons.download_outlined,
      labelKey: 'actionSaveToGallery',
      labelEn: 'Save to gallery',
      isAvailable: (entity, ctx) => entity is ResultEntityRef,
    ),
    ActionId.merge: ActionSpec(
      id: ActionId.merge,
      icon: Icons.merge,
      labelKey: 'actionMergeWith',
      labelEn: 'Merge with...',
      isAvailable: (entity, ctx) => entity is PersonEntityRef,
    ),
    ActionId.organizeFiles: ActionSpec(
      id: ActionId.organizeFiles,
      icon: Icons.drive_file_move_outlined,
      labelKey: 'actionOrganizeFiles',
      labelEn: 'Organize files',
      isAvailable: (entity, ctx) =>
          entity is PersonEntityRef || entity is GroupEntityRef,
    ),
    ActionId.exportDataset: ActionSpec(
      id: ActionId.exportDataset,
      icon: Icons.archive_outlined,
      labelKey: 'actionExportTraining',
      labelEn: 'Export training',
      isAvailable: (entity, ctx) => entity is DatasetEntityRef,
    ),
    ActionId.analyzeNow: ActionSpec(
      id: ActionId.analyzeNow,
      icon: Icons.document_scanner_outlined,
      labelKey: 'actionAnalyzeNow',
      labelEn: 'Analyze now',
      isAvailable: (entity, ctx) =>
          entity is MediaEntityRef || entity is AlbumEntityRef,
    ),
    ActionId.redetect: ActionSpec(
      id: ActionId.redetect,
      icon: Icons.refresh,
      labelKey: 'actionRedetect',
      labelEn: 'Redetect',
      isAvailable: (entity, ctx) => entity is MediaEntityRef,
    ),
    ActionId.albumIncludeScan: ActionSpec(
      id: ActionId.albumIncludeScan,
      icon: Icons.add_task,
      labelKey: 'actionAlbumIncludeScan',
      labelEn: 'Include in scan',
      isAvailable: (entity, ctx) => entity is AlbumEntityRef,
    ),
    ActionId.albumExcludeScan: ActionSpec(
      id: ActionId.albumExcludeScan,
      icon: Icons.block,
      labelKey: 'actionAlbumExcludeScan',
      labelEn: 'Exclude from scan',
      isAvailable: (entity, ctx) => entity is AlbumEntityRef,
    ),
    ActionId.albumReview: ActionSpec(
      id: ActionId.albumReview,
      icon: Icons.rate_review_outlined,
      labelKey: 'actionAlbumReview',
      labelEn: 'Review album',
      isAvailable: (entity, ctx) => entity is AlbumEntityRef,
    ),
    ActionId.albumAnalyze: ActionSpec(
      id: ActionId.albumAnalyze,
      icon: Icons.analytics_outlined,
      labelKey: 'actionAlbumAnalyze',
      labelEn: 'Analyze album',
      isAvailable: (entity, ctx) => entity is AlbumEntityRef,
    ),
    ActionId.pause: ActionSpec(
      id: ActionId.pause,
      icon: Icons.pause,
      labelKey: 'actionPause',
      labelEn: 'Pause',
      isAvailable: (entity, ctx) => entity is JobEntityRef,
    ),
    ActionId.resume: ActionSpec(
      id: ActionId.resume,
      icon: Icons.play_arrow,
      labelKey: 'actionResume',
      labelEn: 'Resume',
      isAvailable: (entity, ctx) => entity is JobEntityRef,
    ),
    ActionId.cancel: ActionSpec(
      id: ActionId.cancel,
      icon: Icons.cancel_outlined,
      labelKey: 'actionCancel',
      labelEn: 'Cancel',
      isAvailable: (entity, ctx) => entity is JobEntityRef,
    ),
    ActionId.retry: ActionSpec(
      id: ActionId.retry,
      icon: Icons.replay,
      labelKey: 'actionRetry',
      labelEn: 'Retry',
      isAvailable: (entity, ctx) => entity is JobEntityRef,
    ),

    // -------------------------------------------------------------
    // خطر (Danger)
    // -------------------------------------------------------------
    ActionId.remove: ActionSpec(
      id: ActionId.remove,
      icon: Icons.remove_circle_outline,
      labelKey: 'actionRemove',
      labelEn: 'Remove',
      isDanger: true,
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef ||
          entity is ActionEntityRef ||
          entity is ClusterEntityRef ||
          entity is DatasetEntityRef,
    ),
    ActionId.delete: ActionSpec(
      id: ActionId.delete,
      icon: Icons.delete_outline,
      labelKey: 'actionDelete',
      labelEn: 'Delete',
      isDanger: true,
      isAvailable: (entity, ctx) =>
          entity is FaceEntityRef ||
          entity is PersonEntityRef ||
          entity is GroupEntityRef ||
          entity is ActionEntityRef ||
          entity is ClusterEntityRef ||
          entity is ResultEntityRef ||
          entity is JobEntityRef ||
          entity is ModelEntityRef ||
          entity is DatasetEntityRef,
    ),
  };

  static ActionSpec spec(ActionId id) => _specs[id]!;

  static List<ActionSpec> allSpecs() => _specs.values.toList();

  static List<ActionSpec> specsFor(
    EntityRef entity, [
    ActionContext context = ActionContext.defaultContext,
  ]) => _specs.values.where((s) => s.isAvailable(entity, context)).toList();

  static List<ActionId> actionsFor(
    EntityRef entity, [
    ActionContext context = ActionContext.defaultContext,
  ]) => specsFor(entity, context).map((s) => s.id).toList();

  static List<ActionId> quickActionsFor(
    EntityRef entity, [
    ActionContext context = ActionContext.defaultContext,
  ]) {
    if (entity is MediaEntityRef) {
      return [ActionId.info, ActionId.share];
    }
    if (entity is FaceEntityRef) {
      return [ActionId.assignPerson, ActionId.refaceThis];
    }
    if (entity is BodyEntityRef) {
      return [
        ActionId.openPhoto,
        ActionId.similarPose,
        ActionId.similarColours,
        ActionId.markTattoo,
        ActionId.namePose,
        ActionId.restyleThis,
      ];
    }
    if (entity is PersonEntityRef) {
      final list = [ActionId.rename];
      if (!entity.isCharacter && !context.isCharacter) {
        list.addAll([ActionId.refaceWith, ActionId.trainModel]);
      }
      return list;
    }
    if (entity is GroupEntityRef) {
      return [ActionId.rename];
    }
    if (entity is ActionEntityRef) {
      return [ActionId.rename];
    }
    if (entity is ClusterEntityRef) {
      return [ActionId.rename];
    }
    if (entity is ResultEntityRef) {
      return [ActionId.runAgain, ActionId.share, ActionId.saveToGallery];
    }
    if (entity is ModelEntityRef) {
      return [ActionId.generateWith];
    }
    if (entity is DatasetEntityRef) {
      return [ActionId.trainModel];
    }
    return const [];
  }

  static List<ActionId> bulkActionsFor(
    List<EntityRef> entities, [
    ActionContext context = ActionContext.defaultContext,
  ]) {
    if (entities.isEmpty) return const [];
    var common = actionsFor(entities.first, context).toSet();
    for (var i = 1; i < entities.length; i++) {
      common = common.intersection(actionsFor(entities[i], context).toSet());
    }
    return common.toList();
  }
}
