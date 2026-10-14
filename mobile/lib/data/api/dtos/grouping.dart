import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'embedding.dart';
import 'json_util.dart';

// openapi.yaml: GroupingPlanRequest / GroupingPlanResponse. The phone sends embeddings, the PC
// answers with decisions (person_linking via grouping_core). Nothing is stored on the PC.

const groupingStages = ['match', 'cluster', 'duplicates', 'bodies'];

class GroupingModel {
  const GroupingModel({
    required this.pid,
    required this.proto,
    required this.members,
    required this.count,
  });

  final int pid;
  final Float32List proto; // q^2-weighted mean of ALL the person's faces (unit)
  final List<Float32List> members; // best quality first, capped
  final int count; // how many faces the person has in total

  Map<String, dynamic> toJson() => {
    'pid': pid,
    'proto': encodeEmbedding(proto),
    'members': [for (final m in members) encodeEmbedding(m)],
    'count': count,
  };

  factory GroupingModel.fromJson(Map<String, dynamic> json) => GroupingModel(
    pid: integer(json, 'pid', 'models[]'),
    proto: decodeEmbedding(field<String>(json, 'proto', 'models[]')),
    members: [
      for (final m in list(json['members'], 'models[].members'))
        decodeEmbedding(m as String),
    ],
    count: integer(json, 'count', 'models[]'),
  );
}

class GroupingFace {
  const GroupingFace({
    required this.id,
    required this.embedding,
    required this.quality,
    this.frameKey,
    this.rejectedPersonIds = const [],
  });

  final int id;
  final Float32List embedding;
  final double quality;

  /// Faces with the same key are in the same photo/frame and cannot be one person.
  final String? frameKey;
  final List<int> rejectedPersonIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'embedding': encodeEmbedding(embedding),
    'quality': quality,
    'frame_key': frameKey,
    'rejected_person_ids': rejectedPersonIds,
  };

  factory GroupingFace.fromJson(Map<String, dynamic> json) => GroupingFace(
    id: integer(json, 'id', 'pending[]'),
    embedding: decodeEmbedding(field<String>(json, 'embedding', 'pending[]')),
    quality: number(json, 'quality', 'pending[]'),
    frameKey: json['frame_key'] as String?,
    rejectedPersonIds: [
      for (final p in list(
        json['rejected_person_ids'],
        'pending[].rejected_person_ids',
      ))
        p as int,
    ],
  );
}

class GroupingBody {
  const GroupingBody({
    required this.id,
    this.mediaId,
    this.frameNumber,
    this.anchorPersonId,
    this.appearance,
    this.weakFaceEmbedding,
    this.rejectedPersonIds = const [],
  });

  final int id;
  final int? mediaId;
  final int? frameNumber;
  final int?
  anchorPersonId; // person it already belongs to (face or manual link)
  final List<double>? appearance; // 80-float outfit descriptor
  final Float32List? weakFaceEmbedding;
  final List<int> rejectedPersonIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'media_id': mediaId,
    'frame_number': frameNumber,
    'anchor_person_id': anchorPersonId,
    'appearance': appearance,
    if (weakFaceEmbedding != null)
      'weak_face_embedding': encodeEmbedding(weakFaceEmbedding!),
    'rejected_person_ids': rejectedPersonIds,
  };

  factory GroupingBody.fromJson(Map<String, dynamic> json) {
    final weak = json['weak_face_embedding'];
    final appearance = json['appearance'];
    return GroupingBody(
      id: integer(json, 'id', 'bodies[]'),
      mediaId: json['media_id'] as int?,
      frameNumber: json['frame_number'] as int?,
      anchorPersonId: json['anchor_person_id'] as int?,
      appearance: appearance == null
          ? null
          : numbers(appearance, 'bodies[].appearance'),
      weakFaceEmbedding: weak is String ? decodeEmbedding(weak) : null,
      rejectedPersonIds: [
        for (final p in list(
          json['rejected_person_ids'],
          'bodies[].rejected_person_ids',
        ))
          p as int,
      ],
    );
  }
}

class GroupingPlanRequest {
  const GroupingPlanRequest({
    required this.mode,
    required this.stages,
    required this.strictness,
    required this.models,
    required this.pending,
    this.dismissedFaceIds = const [],
    this.distinctPairs = const [],
    this.bodies = const [],
    this.maxSuggestionsPerPerson = 60,
  });

  final String mode; // apply | review
  final List<String> stages;
  final String strictness; // strict | balanced | loose
  final List<GroupingModel> models;
  final List<GroupingFace> pending;
  final List<int> dismissedFaceIds;
  final List<(int, int)> distinctPairs;
  final List<GroupingBody> bodies;
  final int maxSuggestionsPerPerson;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'stages': stages,
    'strictness': strictness,
    'models': [for (final m in models) m.toJson()],
    'pending': [for (final f in pending) f.toJson()],
    'dismissed_face_ids': dismissedFaceIds,
    'distinct_pairs': [
      for (final (a, b) in distinctPairs) [a, b],
    ],
    'bodies': [for (final b in bodies) b.toJson()],
    'max_suggestions_per_person': maxSuggestionsPerPerson,
  };

  factory GroupingPlanRequest.fromJson(Map<String, dynamic> json) =>
      GroupingPlanRequest(
        mode: field<String>(json, 'mode'),
        stages: [for (final s in list(json['stages'], 'stages')) s as String],
        strictness: field<String>(json, 'strictness'),
        models: [
          for (final m in list(json['models'], 'models'))
            GroupingModel.fromJson(map(m, 'models[]')),
        ],
        pending: [
          for (final f in list(json['pending'], 'pending'))
            GroupingFace.fromJson(map(f, 'pending[]')),
        ],
        dismissedFaceIds: [
          for (final i in list(
            json['dismissed_face_ids'] ?? const [],
            'dismissed_face_ids',
          ))
            i as int,
        ],
        distinctPairs: [
          for (final p in list(json['distinct_pairs'], 'distinct_pairs'))
            ((p as List)[0] as int, p[1] as int),
        ],
        bodies: [
          for (final b in list(json['bodies'], 'bodies'))
            GroupingBody.fromJson(map(b, 'bodies[]')),
        ],
        maxSuggestionsPerPerson:
            (json['max_suggestions_per_person'] as int?) ?? 60,
      );

  /// The request body exactly as it goes on the wire: JSON, gzipped (a first scan is several MB of
  /// base64 embeddings). Heavy - call it off the UI isolate.
  Uint8List encodeGzip() =>
      Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(toJson()))));
}

class FaceAssignment {
  const FaceAssignment({
    required this.faceId,
    required this.personId,
    required this.score,
    required this.margin,
    required this.decision,
  });

  final int faceId;
  final int personId;
  final double score;
  final double margin;
  final String decision; // auto | suggest

  bool get isAuto => decision == 'auto';

  factory FaceAssignment.fromJson(Map<String, dynamic> json) => FaceAssignment(
    faceId: integer(json, 'face_id', 'assignments[]'),
    personId: integer(json, 'person_id', 'assignments[]'),
    score: number(json, 'score', 'assignments[]'),
    margin: number(json, 'margin', 'assignments[]'),
    decision: field<String>(json, 'decision', 'assignments[]'),
  );

  Map<String, dynamic> toJson() => {
    'face_id': faceId,
    'person_id': personId,
    'score': score,
    'margin': margin,
    'decision': decision,
  };
}

class FaceGroup {
  const FaceGroup({
    required this.faceIds,
    required this.cohesion,
    required this.quality,
    required this.autoCreate,
  });

  final List<int> faceIds;
  final double cohesion;
  final double quality;
  final bool
  autoCreate; // big and cohesive enough that apply mode makes a person

  factory FaceGroup.fromJson(Map<String, dynamic> json) => FaceGroup(
    faceIds: [
      for (final i in list(json['face_ids'], 'groups[].face_ids')) i as int,
    ],
    cohesion: number(json, 'cohesion', 'groups[]'),
    quality: number(json, 'quality', 'groups[]'),
    autoCreate: field<bool>(json, 'auto_create', 'groups[]'),
  );

  Map<String, dynamic> toJson() => {
    'face_ids': faceIds,
    'cohesion': cohesion,
    'quality': quality,
    'auto_create': autoCreate,
  };
}

class DuplicatePeople {
  const DuplicatePeople({
    required this.personA,
    required this.personB,
    required this.score,
  });

  final int personA;
  final int personB;
  final double score;

  factory DuplicatePeople.fromJson(Map<String, dynamic> json) =>
      DuplicatePeople(
        personA: integer(json, 'person_a', 'duplicates[]'),
        personB: integer(json, 'person_b', 'duplicates[]'),
        score: number(json, 'score', 'duplicates[]'),
      );

  Map<String, dynamic> toJson() => {
    'person_a': personA,
    'person_b': personB,
    'score': score,
  };
}

class BodyLinkPlan {
  const BodyLinkPlan({
    required this.bodyId,
    required this.personId,
    required this.method,
    required this.confidence,
    required this.decision,
  });

  final int bodyId;
  final int personId;
  final String method; // appearance | weak_face
  final double confidence;
  final String decision; // auto | suggest

  bool get isAuto => decision == 'auto';

  factory BodyLinkPlan.fromJson(Map<String, dynamic> json) => BodyLinkPlan(
    bodyId: integer(json, 'body_id', 'body_links[]'),
    personId: integer(json, 'person_id', 'body_links[]'),
    method: field<String>(json, 'method', 'body_links[]'),
    confidence: number(json, 'confidence', 'body_links[]'),
    decision: field<String>(json, 'decision', 'body_links[]'),
  );

  Map<String, dynamic> toJson() => {
    'body_id': bodyId,
    'person_id': personId,
    'method': method,
    'confidence': confidence,
    'decision': decision,
  };
}

class GroupingPlanResponse {
  const GroupingPlanResponse({
    required this.mode,
    this.assignments = const [],
    this.groups = const [],
    this.duplicates = const [],
    this.bodyLinks = const [],
    this.unsortedFaceIds = const [],
  });

  final String mode;
  final List<FaceAssignment> assignments;
  final List<FaceGroup> groups;
  final List<DuplicatePeople> duplicates;
  final List<BodyLinkPlan> bodyLinks;
  final List<int> unsortedFaceIds;

  factory GroupingPlanResponse.fromJson(Map<String, dynamic> json) =>
      GroupingPlanResponse(
        mode: field<String>(json, 'mode'),
        assignments: [
          for (final a in list(json['assignments'], 'assignments'))
            FaceAssignment.fromJson(map(a, 'assignments[]')),
        ],
        groups: [
          for (final g in list(json['groups'], 'groups'))
            FaceGroup.fromJson(map(g, 'groups[]')),
        ],
        duplicates: [
          for (final d in list(json['duplicates'], 'duplicates'))
            DuplicatePeople.fromJson(map(d, 'duplicates[]')),
        ],
        bodyLinks: [
          for (final l in list(json['body_links'], 'body_links'))
            BodyLinkPlan.fromJson(map(l, 'body_links[]')),
        ],
        unsortedFaceIds: [
          for (final i in list(json['unsorted_face_ids'], 'unsorted_face_ids'))
            i as int,
        ],
      );

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'assignments': [for (final a in assignments) a.toJson()],
    'groups': [for (final g in groups) g.toJson()],
    'duplicates': [for (final d in duplicates) d.toJson()],
    'body_links': [for (final l in bodyLinks) l.toJson()],
    'unsorted_face_ids': unsortedFaceIds,
  };
}
