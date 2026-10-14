/// How many member faces per person the phone sends to POST /v1/grouping/plan, best quality first.
///
/// The PC's own gallery uses 300 (`person_linking.build_person_models`). Only face -> person matching
/// is affected by the cap (the "3 most similar members" half of the score; the prototype always uses
/// every face and the PC reads just the first 50 members for duplicate-person scoring), and the
/// payload is roughly `people x cap x 2 KB`. `eval_member_cap.py` measures 300/200/150/100/75/50 on a
/// curated library against the PC's own numbers and prints the smallest cap that keeps accuracy:
/// change this one constant if its answer differs. It must stay >= 50.
const groupingMemberCap = 100;

/// The Review screen shows at most this many suggested faces per person (review_state's default).
const groupingMaxSuggestionsPerPerson = 60;

/// Stages of the three rounds (see openapi.yaml, POST /v1/grouping/plan).
const round1Stages = ['match', 'cluster'];
const round2Stages = ['bodies'];
const round3Stages = ['match', 'cluster', 'duplicates', 'bodies'];

/// A scan asks the PC to group after this many new faces / photos (and always when it ends).
const groupEveryNewFaces = 25;
const groupEveryPhotos = 60;
