"""Desktop persistence of character samples. Never used by the stateless API."""
from datetime import datetime, timezone

from character_detection import AUTO_MATCH, MATCH_MARGIN, MODEL_ID, similarity


def store_character(db, character, media_id, frame, timestamp, crop_dir, img, used_samples=None):
    from pathlib import Path
    from analysis import body_crop
    from library_scanner import imwrite
    box = [round(float(v), 1) for v in character.bbox]
    occupied = set()
    used_samples = used_samples if used_samples is not None else set()
    for sample in db.character_samples.values():
        if sample['media_id'] != media_id or sample.get('frame_number') != frame:
            continue
        occupied.add(sample['identity_id'])
        a, b = box, sample['bbox']
        inter = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
        union = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - inter
        if sample['id'] not in used_samples and union > 0 and inter / union >= .65:
            used_samples.add(sample['id'])
            return sample['id'], False
    candidates = {}
    counts = {}
    for sample in sorted(db.character_samples.values(), key=lambda s: (-s['score'], -s['id'])):
        pid = sample['identity_id']
        if pid in occupied or sample['model_id'] != MODEL_ID or counts.get(pid, 0) >= 12:
            continue
        counts[pid] = counts.get(pid, 0) + 1
        candidates[pid] = max(candidates.get(pid, 0), similarity(character.descriptor, sample['descriptor']))
    ranked = sorted(candidates.items(), key=lambda p: (-p[1], p[0]))
    pid = None
    if ranked and ranked[0][1] >= AUTO_MATCH and ranked[0][1] - (ranked[1][1] if len(ranked) > 1 else 0) >= MATCH_MARGIN:
        pid = ranked[0][0]
    now = datetime.now(timezone.utc).isoformat()
    if pid is None:
        pid = db.next_character_identity_id
        db.next_character_identity_id += 1
        db.character_identities[pid] = dict(id=pid, name=None, created_at=now)
    cid = db.next_character_sample_id
    db.next_character_sample_id += 1
    path = Path(crop_dir) / f'{cid}.jpg'
    saved = imwrite(path, body_crop(img, character.bbox))
    db.character_samples[cid] = dict(id=cid, identity_id=pid, model_id=character.model_id,
        descriptor=[round(float(v), 6) for v in character.descriptor], bbox=box,
        score=float(character.score), media_id=media_id, frame_number=frame,
        timestamp=timestamp, crop_path=str(path) if saved else None, created_at=now)
    db.save_db()
    used_samples.add(cid)
    return cid, True
