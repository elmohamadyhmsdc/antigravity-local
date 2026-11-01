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
//   v12 + faces/bodies.track_id (a person's continuous appearance in one video)
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

  // v14: 'person' | 'character' (a drawn figure). Characters live in the same tables and
  // go through the same grouping/review/merge code, but every people query is scoped by kind.
  TextColumn get kind => text().withDefault(const Constant('person'))();
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

  // v11: in an album the user marked as anime/cartoon (scanned for characters)
  BoolColumn get illustrated => boolean().withDefault(const Constant(false))();

  // v16 (roadmap section 8): `isSensitive` is a DERIVED cache of (sensitive_regions, the per-label
  // thresholds, regions' user_state, sensitiveOverride) - recomputed by sensitive_policy.dart whenever
  // one of them changes, never edited on its own. `sensitiveOverride`: the user's word, 'none' |
  // 'sensitive'. `sensitiveVersion`: the PC model version whose regions this file has (0 = never
  // checked); a photo with no regions still has a version, so the backfill does not redo it forever.
  TextColumn get sensitiveOverride => text().nullable()();
  BoolColumn get isSensitive => boolean().withDefault(const Constant(false))();
  IntColumn get sensitiveVersion => integer().withDefault(const Constant(0))();

  // v16: the DINOv2 pass (roadmap 7.5) for this photo was done by /v1/analyze/sensitive?embeddings (0 = not yet).
  // A photo scanned with return_body_embeddings gets it from the scan itself.
  IntColumn get bodyEmbeddingVersion =>
      integer().withDefault(const Constant(0))();

  // v16 (roadmap Phase 7): the PC garment-tag version whose tags this photo's bodies have (0 = never asked).
  IntColumn get garmentVersion => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'faces_person_id', columns: {#personId})
@TableIndex(name: 'faces_media_id', columns: {#mediaId})
@TableIndex(name: 'faces_track_id', columns: {#trackId})
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

  // v12: one appearance of a person in a video. Every face of it shares the id of
  // its first face; only a few varied views are rows, other frames are detections.
  IntColumn get trackId => integer().nullable()();

  // v14: 'person' | 'character' - a drawn face (model ccip-caformer24@1, 768-d embedding).
  TextColumn get kind => text().withDefault(const Constant('person'))();
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

/// v15: the user's "this is a person / a character" corrections, sent with every scan of
/// the file so a rescan never undoes them. Keyed by asset (like suppressions) so they survive
/// the media row being removed and imported again. `part` null = the whole file;
/// 'face' | 'body' = one detection at the normalised box (and, in a video, time).
/// `targetPersonId`: what the next scan finds there joins that person or character, once.
@TableIndex(name: 'kind_overrides_asset', columns: {#assetId})
@DataClassName('KindOverrideRow')
class KindOverrides extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetId => text()();
  TextColumn get kind => text()(); // 'person' | 'character'
  TextColumn get part =>
      text().nullable()(); // 'face' | 'body', null = whole file
  RealColumn get x => real().nullable()();
  RealColumn get y => real().nullable()();
  RealColumn get w => real().nullable()();
  RealColumn get h => real().nullable()();
  IntColumn get timestampMs => integer().nullable()();
  IntColumn get targetPersonId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get createdAt => integer()();
}

@TableIndex(name: 'bodies_media_id', columns: {#mediaId})
@TableIndex(name: 'bodies_person_id', columns: {#personId})
@TableIndex(name: 'bodies_face_id', columns: {#faceId})
@TableIndex(name: 'bodies_track_id', columns: {#trackId})
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
      text().nullable()(); // manual | appearance | weak_face | event_outfit
  RealColumn get linkConfidence => real().nullable()();
  BlobColumn get weakFaceEmbedding => blob().nullable()();
  RealColumn get weakFaceQuality => real().nullable()();
  IntColumn get frameNumber => integer().nullable()();
  IntColumn get timestampMs => integer().nullable()();
  TextColumn get cropPath => text().nullable()();
  IntColumn get createdAt => integer()();

  // v12: like faces.track_id, in the bodies' own id space.
  IntColumn get trackId => integer().nullable()();

  // v14: 'person' | 'character'
  TextColumn get kind => text().withDefault(const Constant('person'))();

  // v16 (roadmap section 7.5, Phase 8): exposed-region embeddings (DINOv2 ViT-S/14, 384 x float32),
  // their clusters, and the morphology JSON {scale_source, breast_span_ratio, areola_contrast,
  // hip_waist_ratio, buttocks_span_ratio, skin_tone_lab, micro_marks}. Written in place by a rescan,
  // never touched by the body UPDATE of the scan store unless the PC returned them.
  BlobColumn get chestEmbedding => blob().nullable()();
  BlobColumn get buttocksEmbedding => blob().nullable()();
  @ReferenceName('chestClusterBodies')
  IntColumn get chestClusterId => integer().nullable().references(
    BodyClusters,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('buttocksClusterBodies')
  IntColumn get buttocksClusterId => integer().nullable().references(
    BodyClusters,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get morphology => text().nullable()();
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

  // v13: flat JSON [x1, y1, x2, y2, ...] normalised to detection box
  TextColumn get outline => text().nullable()();
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

  // v14: 'person' | 'character' - each kind's review plan is replaced on its own.
  TextColumn get kind => text().withDefault(const Constant('person'))();
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
  TextColumn get method => text()(); // appearance | weak_face | event_outfit
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

// ---- v16: body pose / outfit categories, sensitive regions, exposed-body clusters, marks ----------
// (docs/body-pose-and-clothing-filters-roadmap.md sections 6.4, 7.4, 7.5, 8.3)

/// Exposed-region body groups found on the phone (section 7.5). `person_id` is a cache: the single
/// source of truth for attribution is `bodies.person_id` + `link_method`, so deleting a person must
/// not delete the clustering work (set null, not cascade).
@TableIndex(name: 'body_clusters_person', columns: {#personId})
@DataClassName('BodyClusterRow')
class BodyClusters extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text().withDefault(const Constant('person'))();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get clusterType => text()(); // 'chest' | 'buttocks'
  BlobColumn get centroidEmbedding => blob()(); // 384 x float32
  IntColumn get bodyCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
}

/// A tattoo the user marked on a body of a known person (section 7.4).
@TableIndex(name: 'body_marks_person', columns: {#personId})
@DataClassName('BodyMarkRow')
class BodyMarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get personId =>
      integer().references(Persons, #id, onDelete: KeyAction.cascade)();
  IntColumn get sourceBodyId => integer().nullable().references(
    Bodies,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get segment => text()(); // 'r_forearm', 'chest', 'upper_back', ...
  TextColumn get anchor =>
      text()(); // JSON: patch box relative to the segment's anchor keypoints
  TextColumn get patchPath =>
      text()(); // relative, 'marks/<id>.png' (in the backup)
  TextColumn get label => text().nullable()();
  IntColumn get createdAt => integer()();
}

/// Cached pose descriptor; rebuilt when the version or the body's kpts change. Not backed up.
@DataClassName('BodyPoseFeatureRow')
class BodyPoseFeatures extends Table {
  IntColumn get bodyId =>
      integer().references(Bodies, #id, onDelete: KeyAction.cascade)();
  IntColumn get version => integer()();
  BlobColumn get feature => blob()(); // 34 x float32, normalised (section 2.3)
  IntColumn get visibleMask => integer()(); // 17 bits
  TextColumn get scaleSource =>
      text()(); // 'torso' | 'shoulder': compared like-for-like only
  TextColumn get tags => text().withDefault(
    const Constant(''),
  )(); // tier-A labels, comma separated

  @override
  Set<Column> get primaryKey => {bodyId};
}

@DataClassName('PoseCategoryRow')
class PoseCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get kind => text().withDefault(const Constant('person'))();
  IntColumn get exemplarBodyId => integer().nullable().references(
    Bodies,
    #id,
    onDelete: KeyAction.setNull,
  )();
  BlobColumn get exemplarFeature =>
      blob()(); // copy, survives the body's deletion
  IntColumn get exemplarMask => integer()();
  TextColumn get exemplarScaleSource => text()();
  RealColumn get threshold => real()();
  IntColumn get createdAt => integer()();
}

@DataClassName('OutfitCategoryRow')
class OutfitCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get kind => text().withDefault(const Constant('person'))();
  IntColumn get personId => integer().nullable().references(
    Persons,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get exemplarBodyId => integer().nullable().references(
    Bodies,
    #id,
    onDelete: KeyAction.setNull,
  )();
  BlobColumn get exemplarAppearance => blob()(); // 80 x float32 copy
  BoolColumn get lowerOnly => boolean().withDefault(const Constant(false))();
  RealColumn get threshold => real()();
  IntColumn get createdAt => integer()();
}

/// state: 'auto' | 'manual' | 'rejected' (the user removed it - never re-added).
@TableIndex(name: 'body_pose_matches_cat', columns: {#categoryId})
@DataClassName('BodyPoseMatchRow')
class BodyPoseMatches extends Table {
  IntColumn get bodyId =>
      integer().references(Bodies, #id, onDelete: KeyAction.cascade)();
  IntColumn get categoryId =>
      integer().references(PoseCategories, #id, onDelete: KeyAction.cascade)();
  RealColumn get similarity => real()();
  TextColumn get state => text()();

  @override
  Set<Column> get primaryKey => {bodyId, categoryId};
}

@TableIndex(name: 'body_outfit_matches_cat', columns: {#categoryId})
@DataClassName('BodyOutfitMatchRow')
class BodyOutfitMatches extends Table {
  IntColumn get bodyId =>
      integer().references(Bodies, #id, onDelete: KeyAction.cascade)();
  IntColumn get categoryId => integer().references(
    OutfitCategories,
    #id,
    onDelete: KeyAction.cascade,
  )();
  RealColumn get similarity => real()();
  TextColumn get state => text()();

  @override
  Set<Column> get primaryKey => {bodyId, categoryId};
}

/// Exposed / covered body-part boxes from the PC (NudeNet, section 8). Local to the phone; no crops
/// of these areas are stored anywhere.
@TableIndex(name: 'sensitive_regions_media', columns: {#mediaId})
@TableIndex(name: 'sensitive_regions_body', columns: {#bodyId})
@DataClassName('SensitiveRegionRow')
class SensitiveRegions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mediaId =>
      integer().references(Media, #id, onDelete: KeyAction.cascade)();
  IntColumn get bodyId => integer().nullable().references(
    Bodies,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get label => text()();
  BoolColumn get exposed => boolean()();
  RealColumn get score => real()();
  RealColumn get x => real()(); // normalised to the image
  RealColumn get y => real()();
  RealColumn get w => real()();
  RealColumn get h => real()();
  IntColumn get frameNumber => integer().nullable()();
  IntColumn get timestampMs => integer().nullable()();
  IntColumn get modelVersion => integer()();
  TextColumn get userState => text().nullable()(); // 'dismissed' | 'confirmed'
  IntColumn get createdAt => integer()();
}

/// Raw WD14 garment scores per body (roadmap Phase 7). Evidence for the user's own labelling: nothing
/// reads these as a filter until a tag's precision on real photos has been measured. Kept per body so a
/// deleted body takes its tags with it; `score` is the tagger's probability, not a decision.
@TableIndex(name: 'body_garment_tags_tag', columns: {#tag})
@DataClassName('BodyGarmentTagRow')
class BodyGarmentTags extends Table {
  IntColumn get bodyId =>
      integer().references(Bodies, #id, onDelete: KeyAction.cascade)();
  TextColumn get tag => text()();
  TextColumn get category => text()();
  RealColumn get score => real()();

  @override
  Set<Column> get primaryKey => {bodyId, tag};
}
