// Local schema (plan section 5). It mirrors the PC's JSON store so the inputs of
// person_linking (embeddings, quality, per-frame keys, rejections) are always on
// the phone. Bounding boxes are normalised 0..1 of the analysed image; originals
// are referenced by their MediaStore asset id and never copied.
//
// Schema history (see AppDatabase.migration):
//   v1  persons, media, faces, bodies, face/body rejections, person_distinct, servers, settings
//   v2  + upload_queue, blob_hints (resumable upload bookkeeping for the scan pipeline)
//   v3  + media.taken_at/scan_attempts/scan_error (the scan queue IS the media table: scan_status),
//       media_detections (every face/body seen in a photo, incl. faces linked to an earlier copy),
//       review_matches/groups/duplicates/body_links (the PC's last "review" plan), indexes
// Tables for later phases (identity_sets, loras, lora_dataset_items, jobs, results)
// arrive with their phase as new migration steps.

import 'package:drift/drift.dart';

@DataClassName('PersonRow')
class Persons extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable()();
  IntColumn get avatarFaceId => integer().nullable()();
  IntColumn get createdAt => integer()(); // epoch ms
}

@TableIndex(name: 'media_scan_status', columns: {#scanStatus})
@DataClassName('MediaRow')
class Media extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetId => text().unique()(); // MediaStore / photo_manager id
  TextColumn get kind => text()(); // 'photo' | 'video'
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get modifiedAt =>
      integer().withDefault(const Constant(0))(); // epoch ms
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get scanStatus => text().withDefault(
    const Constant('pending'),
  )(); // pending|scanning|done|failed
  IntColumn get scanVersion => integer().withDefault(const Constant(0))();
  IntColumn get lastScannedFrame => integer().withDefault(const Constant(0))();
  IntColumn get scannedAt => integer().nullable()();

  // v3
  IntColumn get takenAt =>
      integer().nullable()(); // epoch ms (MediaStore creation date)
  IntColumn get scanAttempts => integer().withDefault(const Constant(0))();
  TextColumn get scanError => text().nullable()();
}

@TableIndex(name: 'faces_person_id', columns: {#personId})
@TableIndex(name: 'faces_media_id', columns: {#mediaId})
@DataClassName('FaceRow')
class Faces extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mediaId => integer().nullable().references(
    Media,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get modelId =>
      text()(); // embedding model, e.g. buffalo_l@1 - never mix models
  BlobColumn get embedding =>
      blob()(); // 512 x float32 little-endian (2048 bytes), unit length
  RealColumn get qualityScore => real()();
  IntColumn get qualityVersion => integer()();
  RealColumn get detScore => real()();
  RealColumn get facePx => real()();
  RealColumn get sharpness => real()();
  RealColumn get embeddingNorm => real().nullable()();
  RealColumn get yaw => real().nullable()();
  RealColumn get pitch => real().nullable()();
  RealColumn get roll => real().nullable()();
  RealColumn get bboxX => real()();
  RealColumn get bboxY => real()();
  RealColumn get bboxW => real()();
  RealColumn get bboxH => real()();
  TextColumn get kps => text().nullable()(); // JSON [[x,y] x5], normalised
  IntColumn get frameNumber => integer().nullable()();
  IntColumn get timestampMs => integer().nullable()();
  TextColumn get cropPath => text().nullable()();
  BoolColumn get reviewDismissed =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
}

@TableIndex(name: 'bodies_media_id', columns: {#mediaId})
@TableIndex(name: 'bodies_person_id', columns: {#personId})
@TableIndex(name: 'bodies_face_id', columns: {#faceId})
@DataClassName('BodyRow')
class Bodies extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mediaId => integer().nullable().references(
    Media,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get faceId => integer().nullable().references(
    Faces,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  RealColumn get bboxX => real()();
  RealColumn get bboxY => real()();
  RealColumn get bboxW => real()();
  RealColumn get bboxH => real()();
  RealColumn get score => real()();
  TextColumn get kpts =>
      text().nullable()(); // JSON [[x,y,score] x17], normalised
  TextColumn get extent => text().nullable()(); // full | knee | upper | head
  BlobColumn get appearance =>
      blob().nullable()(); // 80 x float32 outfit descriptor
  TextColumn get linkMethod =>
      text().nullable()(); // manual | appearance | weak_face
  RealColumn get linkConfidence => real().nullable()();
  BlobColumn get weakFaceEmbedding => blob().nullable()();
  RealColumn get weakFaceQuality => real().nullable()();
  IntColumn get frameNumber => integer().nullable()();
  IntColumn get timestampMs => integer().nullable()();
  TextColumn get cropPath => text().nullable()();
  IntColumn get createdAt => integer()();
}

/// "This face is not that person" - auto-grouping never redoes a correction.
@TableIndex(name: 'face_rejections_person_id', columns: {#personId})
@DataClassName('FaceRejectionRow')
class FaceRejections extends Table {
  IntColumn get faceId =>
      integer().references(Faces, #id, onDelete: KeyAction.cascade)();
  IntColumn get personId =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {faceId, personId};
}

@DataClassName('BodyRejectionRow')
class BodyRejections extends Table {
  IntColumn get bodyId =>
      integer().references(Bodies, #id, onDelete: KeyAction.cascade)();
  IntColumn get personId =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {bodyId, personId};
}

/// "These two people are different" (stored with personA < personB).
@DataClassName('PersonDistinctRow')
class PersonDistinct extends Table {
  @ReferenceName('distinctAsA')
  IntColumn get personA =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('distinctAsB')
  IntColumn get personB =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {personA, personB};
}

/// A paired PC. The bearer token is NOT here - it lives in the Android Keystore (secure storage).
@DataClassName('ServerRow')
class Servers extends Table {
  TextColumn get id => text()(); // server_id from /v1/health
  TextColumn get name => text()();
  TextColumn get host => text()();
  IntColumn get port => integer()();
  TextColumn get fingerprint =>
      text()(); // pinned certificate SHA-256, lowercase hex
  IntColumn get pairedAt => integer()();
  IntColumn get lastSeenAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ---- v2 ----------------------------------------------------------------------

/// Files waiting to be uploaded to the PC (resumable; survives an app kill).
@DataClassName('UploadQueueRow')
class UploadQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sha256 => text()();
  TextColumn get localPath =>
      text()(); // staged file in the app's private storage
  IntColumn get sizeBytes => integer()();
  IntColumn get uploadedBytes => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(
    const Constant('queued'),
  )(); // queued|uploading|done|failed
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer()();
}

/// What the PC's blob cache is believed to hold (a hint only - the PC may have evicted it; a 409 is authoritative).
@DataClassName('BlobHintRow')
class BlobHints extends Table {
  TextColumn get sha256 => text()();
  TextColumn get serverId => text()();
  IntColumn get sizeBytes => integer()();
  IntColumn get lastSeenAt => integer()();

  @override
  Set<Column> get primaryKey => {sha256, serverId};
}

// ---- v3 ----------------------------------------------------------------------

/// Every face / body found in a media file, with its normalised box. A face that was linked to
/// an earlier copy of the same face (duplicate rule) has no row of its own in `faces` for this
/// file - this table is what still says "this person is in this photo".
@TableIndex(name: 'media_detections_media_id', columns: {#mediaId})
@TableIndex(name: 'media_detections_ref', columns: {#kind, #refId})
@DataClassName('DetectionRow')
class MediaDetections extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mediaId =>
      integer().references(Media, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()(); // 'f' face | 'b' body
  IntColumn get refId => integer()(); // faces.id or bodies.id
  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get w => real()();
  RealColumn get h => real()();
  IntColumn get frameNumber => integer().nullable()();
  IntColumn get timestampMs => integer().nullable()();
}

/// The PC's last review plan, stored so the Review screen opens instantly and works offline.
/// All four tables are replaced together after every grouping run (never edited by the PC).
@DataClassName('ReviewMatchRow')
class ReviewMatches extends Table {
  IntColumn get faceId =>
      integer().references(Faces, #id, onDelete: KeyAction.cascade)();
  IntColumn get personId =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();
  RealColumn get score => real()();
  RealColumn get margin => real()();
  TextColumn get decision => text()(); // auto | suggest

  @override
  Set<Column> get primaryKey => {faceId};
}

@DataClassName('ReviewGroupRow')
class ReviewGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get faceIds => text()(); // JSON [id, ...]
  RealColumn get cohesion => real()();
  RealColumn get quality => real()();
  BoolColumn get autoCreate => boolean().withDefault(const Constant(false))();
}

@DataClassName('ReviewDuplicateRow')
class ReviewDuplicates extends Table {
  @ReferenceName('reviewDuplicateAsA')
  IntColumn get personA =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('reviewDuplicateAsB')
  IntColumn get personB =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();
  RealColumn get score => real()();

  @override
  Set<Column> get primaryKey => {personA, personB};
}

@DataClassName('ReviewBodyLinkRow')
class ReviewBodyLinks extends Table {
  IntColumn get bodyId =>
      integer().references(Bodies, #id, onDelete: KeyAction.cascade)();
  IntColumn get personId =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();
  TextColumn get method => text()(); // appearance | weak_face
  RealColumn get confidence => real()();

  @override
  Set<Column> get primaryKey => {bodyId};
}
