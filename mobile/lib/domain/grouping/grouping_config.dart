/// How many member faces per person the phone sends to POST /v1/grouping/plan, best quality first.
///
/// The PC's own gallery uses 300 (`person_linking.build_person_models`). Only face -> person matching
/// is affected by the cap (the "3 most similar members" half of the score; the prototype always uses
/// every face and the PC reads just the first 50 members for duplicate-person scoring), and the
/// payload is roughly `people x cap x 2 KB`. `eval_member_cap.py` measures 300/200/150/100/75/50 on a
/// curated library against the PC's own numbers and prints the smallest cap that keeps accuracy:
/// change this one constant if its answer differs. It must stay >= 50.
const groupingMemberCap = 100;

/// A request carries `people x members x 2.7 KB` of base64 (float32 does not compress): the PC refuses
/// more than 128 MB on the wire. In a library with hundreds of people the per-person cap is lowered so the
/// whole request stays near this many member vectors (~36k = ~100 MB of JSON, ~75 MB gzipped).
const groupingMemberBudget = 36000;

/// ...but never below this: the match score needs a few members per person.
const groupingMinMemberCap = 30;

/// The per-person member cap for [people] people: [cap], or less when the request would be too big.
int effectiveMemberCap(int people, [int cap = groupingMemberCap]) {
  if (people <= 0 || people * cap <= groupingMemberBudget) return cap;
  final fit = groupingMemberBudget ~/ people;
  return fit < groupingMinMemberCap ? groupingMinMemberCap : fit;
}

/// Faces smaller than this (px, as the PC measured them) are not grouped, matched or used to build a
/// person: too little identity, and in a crowd they are mostly strangers. New scans never store them
/// (`face_quality.MIN_FACE_PX`); this also keeps the ones stored before that out of the maths.
const groupingMinFacePx = 40.0;
const groupingMinCharacterFacePx = 32.0;

/// The Review screen shows at most this many suggested faces per person (review_state's default).
const groupingMaxSuggestionsPerPerson = 60;

/// Stages of the three rounds (see openapi.yaml, POST /v1/grouping/plan).
const round1Stages = ['match', 'cluster'];
const round2Stages = ['bodies'];
const round3Stages = ['match', 'cluster', 'duplicates', 'bodies'];

/// A scan asks the PC to group after this many new faces / photos (and always when it ends).
const groupEveryNewFaces = 100;
const groupEveryPhotos = 200;

/// Drawn characters are grouped with their own thresholds (CCIP embeddings, not ArcFace). The
/// server maps this name to `person_linking.STRICTNESS['character']`.
const characterStrictness = 'character';
