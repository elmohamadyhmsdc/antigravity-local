/// SQL fragments take internal SQL expressions, never user input.
/// Include canonical rows and every alias/compacted video occurrence. Legacy
/// video detections without a frame cannot prove simultaneous appearances.
String faceOccurrences(String faceId) =>
    '''
  SELECT source.media_id, source.frame_number FROM faces source
  WHERE source.id = $faceId AND source.media_id IS NOT NULL
  UNION
  SELECT d.media_id, d.frame_number FROM media_detections d
  JOIN media m ON m.id = d.media_id
  WHERE d.kind = 'f' AND d.ref_id = $faceId
    AND (m.kind = 'photo' OR d.frame_number IS NOT NULL)
''';

String faceConflictWithPerson(String faceId, String personId) =>
    '''
  EXISTS (
    SELECT 1 FROM (${faceOccurrences(faceId)}) candidate
    JOIN faces other ON other.person_id = $personId AND other.id != $faceId
      AND other.hidden = 0 AND (other.ownership IS NULL OR other.ownership != 'none')
    WHERE EXISTS (
      SELECT 1 FROM (${faceOccurrences('other.id')}) occupied
      WHERE occupied.media_id = candidate.media_id
        AND occupied.frame_number IS candidate.frame_number
    )
  )
''';

/// A manual owner wins. An observed face that is still ungrouped cannot lend
/// its body to a guessed identity while the face waits for a decision.
String bodyOwner(String body, String face) =>
    '''
  CASE
    WHEN $body.hidden = 1 OR $body.ownership = 'none' THEN NULL
    WHEN $body.link_method = 'manual' OR $body.face_id IS NULL THEN $body.person_id
    WHEN $face.hidden = 0 AND $face.ownership IS NOT 'none'
      AND NOT EXISTS (SELECT 1 FROM body_rejections r
        WHERE r.body_id = $body.id AND r.person_id = $face.person_id)
    THEN $face.person_id
  END
''';

/// A distinct body's face owner matters even when bodies.person_id is null.
String bodyConflictWithPerson(String bodyId, String personId) =>
    '''
  EXISTS (
    SELECT 1 FROM body_distinct d
    JOIN bodies other ON other.id = CASE WHEN d.body_a = $bodyId THEN d.body_b ELSE d.body_a END
    LEFT JOIN faces owner ON owner.id = other.face_id
    WHERE (d.body_a = $bodyId OR d.body_b = $bodyId)
      AND ${bodyOwner('other', 'owner')} = $personId
  )
''';
