sealed class EntityRef {
  const EntityRef();
}

class MediaEntityRef extends EntityRef {
  const MediaEntityRef(this.id, {this.isVideo = false});
  final int id;
  final bool isVideo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class FaceEntityRef extends EntityRef {
  const FaceEntityRef(this.id, {this.personId, this.mediaId});
  final int id;
  final int? personId;
  final int? mediaId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class BodyEntityRef extends EntityRef {
  const BodyEntityRef(this.id, {this.personId, this.mediaId, this.trackId});
  final int id;
  final int? personId;
  final int? mediaId;
  final int? trackId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SensitiveRegionEntityRef extends EntityRef {
  const SensitiveRegionEntityRef(this.id, {this.mediaId, this.bodyId});
  final int id;
  final int? mediaId;
  final int? bodyId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensitiveRegionEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class EquipmentEntityRef extends EntityRef {
  const EquipmentEntityRef(this.id, {this.mediaId, this.bodyId, this.name});
  final int id;
  final int? mediaId;
  final int? bodyId;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EquipmentEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class PersonEntityRef extends EntityRef {
  const PersonEntityRef(this.id, {this.name, this.isCharacter = false});
  final int id;
  final String? name;
  final bool isCharacter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class GroupEntityRef extends EntityRef {
  const GroupEntityRef(this.id, {this.name});
  final int id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

enum ClusterKind { pose, outfit, groupPose, equipment, mark, action }

class ClusterEntityRef extends EntityRef {
  const ClusterEntityRef(this.kind, this.id, {this.name});
  final ClusterKind kind;
  final int id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterEntityRef &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          id == other.id;

  @override
  int get hashCode => Object.hash(kind, id);
}

class AlbumEntityRef extends EntityRef {
  const AlbumEntityRef(this.id, {this.name});
  final String id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ResultEntityRef extends EntityRef {
  const ResultEntityRef(this.id, {this.jobId, this.sourceMediaId});
  final String id;
  final String? jobId;
  final int? sourceMediaId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class JobEntityRef extends EntityRef {
  const JobEntityRef(this.id, {this.type});
  final String id;
  final String? type;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ModelEntityRef extends EntityRef {
  const ModelEntityRef(this.id, {this.name});
  final String id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DatasetEntityRef extends EntityRef {
  const DatasetEntityRef(this.id, {this.name});
  final String id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatasetEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class ActionEntityRef extends EntityRef {
  const ActionEntityRef(this.id, {this.name});
  final String id;
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionEntityRef &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
