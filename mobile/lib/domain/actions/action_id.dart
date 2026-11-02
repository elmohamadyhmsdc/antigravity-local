enum ActionId {
  // عرض (View)
  open,
  info,
  expand,
  openPhoto,
  openNativePlayer,

  // تعريف (Identity / Linking)
  rename,
  assignPerson,
  setCover,
  moveToGroup,
  markTattoo,
  confirmLink,
  unlink,
  notThisPerson,
  belongsToNoOne,
  notARealThing,
  notSamePerson,
  changeKind,
  changeFileKind,
  setSensitivity,
  addEquipment,
  boxEquipment,
  namePose,
  nameOutfit,
  nameGroupPose,

  // بحث (Search)
  similarPose,
  similarColours,
  similarFaces,
  personMedia,

  // إنشاء (Create / Studio)
  refaceThis,
  refaceWith,
  restyleThis,
  generateWith,
  addToDataset,
  trainModel,
  runAgain,

  // إدارة (Manage)
  share,
  saveToGallery,
  merge,
  organizeFiles,
  exportDataset,
  analyzeNow,
  redetect,
  albumIncludeScan,
  albumExcludeScan,
  albumReview,
  albumAnalyze,
  pause,
  resume,
  cancel,
  retry,

  // خطر (Danger)
  remove,
  delete;

  ActionGroup get group {
    switch (this) {
      case ActionId.open:
      case ActionId.info:
      case ActionId.expand:
      case ActionId.openPhoto:
      case ActionId.openNativePlayer:
        return ActionGroup.view;

      case ActionId.rename:
      case ActionId.assignPerson:
      case ActionId.setCover:
      case ActionId.moveToGroup:
      case ActionId.markTattoo:
      case ActionId.confirmLink:
      case ActionId.unlink:
      case ActionId.notThisPerson:
      case ActionId.belongsToNoOne:
      case ActionId.notARealThing:
      case ActionId.notSamePerson:
      case ActionId.changeKind:
      case ActionId.changeFileKind:
      case ActionId.setSensitivity:
      case ActionId.addEquipment:
      case ActionId.boxEquipment:
      case ActionId.namePose:
      case ActionId.nameOutfit:
      case ActionId.nameGroupPose:
        return ActionGroup.identity;

      case ActionId.similarPose:
      case ActionId.similarColours:
      case ActionId.similarFaces:
      case ActionId.personMedia:
        return ActionGroup.search;

      case ActionId.refaceThis:
      case ActionId.refaceWith:
      case ActionId.restyleThis:
      case ActionId.generateWith:
      case ActionId.addToDataset:
      case ActionId.trainModel:
      case ActionId.runAgain:
        return ActionGroup.create;

      case ActionId.share:
      case ActionId.saveToGallery:
      case ActionId.merge:
      case ActionId.organizeFiles:
      case ActionId.exportDataset:
      case ActionId.analyzeNow:
      case ActionId.redetect:
      case ActionId.albumIncludeScan:
      case ActionId.albumExcludeScan:
      case ActionId.albumReview:
      case ActionId.albumAnalyze:
      case ActionId.pause:
      case ActionId.resume:
      case ActionId.cancel:
      case ActionId.retry:
        return ActionGroup.manage;

      case ActionId.remove:
      case ActionId.delete:
        return ActionGroup.danger;
    }
  }
}

enum ActionGroup { view, identity, search, create, manage, danger }
