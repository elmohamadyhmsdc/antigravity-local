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

@DataClassName('CharacterIdentityRow')
class CharacterIdentities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable()();
  IntColumn get createdAt => integer()();
}

@TableIndex(name: 'character_samples_identity', columns: {#identityId})
@TableIndex(name: 'character_samples_media', columns: {#mediaId})
@DataClassName('CharacterSampleRow')
class CharacterSamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get identityId => integer().references(
    CharacterIdentities,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get mediaId =>
      integer().references(Media, #id, onDelete: KeyAction.cascade)();
  TextColumn get modelId => text()();
  BlobColumn get descriptor => blob()(); // 160 float32, character-appearance@1
  RealColumn get bboxX => real()();
  RealColumn get bboxY => real()();
  RealColumn get bboxW => real()();
  RealColumn get bboxH => real()();
  RealColumn get score => real()();
  IntColumn get frameNumber => integer().nullable()();
  IntColumn get timestampMs => integer().nullable()();
  TextColumn get cropPath => text().nullable()();
  IntColumn get createdAt => integer()();
}

@DataClassName('PersonRow')
class Persons extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable()();
  IntColumn get avatarFaceId => integer().nullable()();
  IntColumn get createdAt => integer()(); // epoch ms
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get groupingLocked =>
      boolean().withDefault(const Constant(false))();
}

/// A reusable choice of real source faces. Deleting a person/face cannot leave
/// dangling references, and selecting a set revalidates current assignments.
@DataClassName('IdentitySetRow')
class IdentitySets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get personId =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get modelId => text()();
  IntColumn get createdAt => integer()();
}

@DataClassName('IdentitySetFaceRow')
class IdentitySetFaces extends Table {
  IntColumn get setId =>
      integer().references(IdentitySets, #id, onDelete: KeyAction.cascade)();
  IntColumn get faceId =>
      integer().references(Faces, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column> get primaryKey => {setId, faceId};
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
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
}

/// Deletion decisions survive rescans and removal/reimport of the media row.
/// Occurrences are normalised [x, y, w, h, frame] boxes; no crop is retained.
@TableIndex(name: 'face_suppressions_asset', columns: {#assetId})
@DataClassName('FaceSuppressionRow')
class FaceSuppressions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetId => text()();
  TextColumn get modelId => text()();
  BlobColumn get embedding => blob()();
  TextColumn get occurrences => text()();
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

// ---- v4: Studio requests are durable before the first network call ------------

@TableIndex(name: 'jobs_status', columns: {#status})
@DataClassName('JobRow')
class Jobs extends Table {
  TextColumn get id => text()(); // phone-generated idempotency key
  TextColumn get serverId => text()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get type => text()();
  TextColumn get requestJson => text()();
  TextColumn get inputFiles =>
      text().withDefault(const Constant('{}'))(); // sha -> relative path
  TextColumn get detailsJson => text().withDefault(const Constant('{}'))();
  TextColumn get targetPath => text()(); // private, relative snapshot
  TextColumn get targetSha => text()();
  IntColumn get targetSize => integer()();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get status =>
      text()(); // uploading|queued|running|paused|downloading|completed|failed|lost
  RealColumn get progress => real().withDefault(const Constant(0))();
  TextColumn get message => text().nullable()();
  TextColumn get error => text().nullable()();
  BoolColumn get acknowledged => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('JobEventRow')
class JobEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get jobId =>
      text().references(Jobs, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => text()();
  TextColumn get message => text().nullable()();
  IntColumn get createdAt => integer()();
}

@TableIndex(name: 'results_created_at', columns: {#createdAt})
@DataClassName('ResultRow')
class Results extends Table {
  TextColumn get id => text()(); // local job id; import is idempotent
  TextColumn get type => text()();
  TextColumn get path => text()();
  TextColumn get originalPath => text()();
  TextColumn get mime => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text()();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  BoolColumn get favourite => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DatasetRow')
class Datasets extends Table {
  TextColumn get id => text()();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get triggerWord => text()();
  IntColumn get repeats => integer().withDefault(const Constant(20))();
  IntColumn get createdAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DatasetItemRow')
class DatasetItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get datasetId =>
      text().references(Datasets, #id, onDelete: KeyAction.cascade)();
  TextColumn get path => text()();
  TextColumn get caption => text()();
  BoolColumn get included => boolean().withDefault(const Constant(true))();
}

@DataClassName('LoraRow')
class Loras extends Table {
  TextColumn get id => text()();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get path => text()();
  TextColumn get triggerWord => text()();
  TextColumn get identityJson =>
      text().nullable()(); // anchor-verified generated portraits
  IntColumn get createdAt => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

// ---- v10: "Not sure" answers from the quick review --------------------------------

/// A quick-review question the user answered "Not sure". It stays out of the quick flow until
/// new evidence arrives: a higher score or more faces than when it was snoozed. Keys follow
/// `ReviewQuestion.key` (m:face:person, g:first face, d:a:b, o:body:person); they outlive the
/// review_* rows, which every grouping run replaces.
@DataClassName('ReviewSnoozeRow')
class ReviewSnoozes extends Table {
  TextColumn get questionKey => text()();
  RealColumn get score => real()();
  IntColumn get evidence =>
      integer()(); // faces behind the question when snoozed
  IntColumn get snoozedAt => integer()();

  @override
  Set<Column> get primaryKey => {questionKey};
}
