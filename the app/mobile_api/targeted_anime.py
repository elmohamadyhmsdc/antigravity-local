"""Explicit anime face recovery. Never used to classify ordinary photo scans."""
import base64

import cv2
import numpy as np

import analysis
from .errors import ApiError

MODEL_ID = "ccip-caformer24@1"


def analyze_anime_face(img, roi=None, high_res=True):
    h, w = img.shape[:2]
    if roi is None:
        x, y, right, bottom = 0, 0, w, h
    else:
        x, y = int(roi['x'] * w), int(roi['y'] * h)
        right = min(w, int(np.ceil((roi['x'] + roi['w']) * w)))
        bottom = min(h, int(np.ceil((roi['y'] + roi['h']) * h)))
    crop = img[y:bottom, x:right]
    if min(crop.shape[:2], default=0) < 8:
        raise ApiError(400, "bad_request", "Select a larger face area (at least 8 pixels per side).")
    detector = analysis.get_anime_detector()
    embedder = analysis.get_ccip_embedder()
    if detector is None or embedder is None:
        raise ApiError(503, "model_missing", "Anime face detection and CCIP models must be installed on the PC.")
    detect = detector.detect_multiscale if high_res and hasattr(detector, 'detect_multiscale') else detector.detect
    # The selected area is enlarged by letterboxing, without lowering confidence.
    hits = detect(crop, score_thresh=analysis.ANIME_CANDIDATE_SCORE)
    ch, cw = crop.shape[:2]
    selected = []
    for hit in hits:
        box = np.asarray(hit['bbox'], dtype=float)
        score = float(hit['score'])
        if (box.shape != (4,) or not np.isfinite(box).all() or not np.isfinite(score)
                or not analysis.ANIME_CANDIDATE_SCORE <= score <= 1):
            continue
        box[:2] = np.maximum(box[:2], 0)
        box[2:] = np.minimum(box[2:], [cw, ch])
        size = box[2:] - box[:2]
        if min(size) < 8 or not .35 <= size[0] / size[1] <= 1.8:
            continue
        if roi is not None:
            centre = (box[:2] + box[2:]) / 2 / [cw, ch]
            # Do not snap the user's box to a tiny bystander near an edge.
            if size.prod() < .15 * cw * ch or np.any(np.abs(centre - .5) > .35):
                continue
        elif score < analysis.ANIME_ILLUSTRATED_SCORE:
            continue
        selected.append((box, score))
    if roi is not None:
        selected.sort(key=lambda hit: -hit[1])
        selected = selected[:1]
        if not selected:
            selected = [(np.array([0, 0, cw, ch], dtype=float), 0.0)]
    from character_embedder import asymmetric_ccip_crop
    results = []
    for local_box, score in selected:
        box = local_box + [x, y, x, y]
        l, t, r, b = asymmetric_ccip_crop(box.tolist(), w, h)
        vector = np.array(embedder.embed_crop(img[t:b, l:r]), dtype='<f4', copy=True)
        if vector.shape != (768,) or not np.isfinite(vector).all() or np.linalg.norm(vector) < 1e-8:
            raise ApiError(503, "analysis_failed", "The PC could not extract a character identity. Try a larger face area.", retryable=True)
        vector /= np.linalg.norm(vector)
        fx1, fy1 = np.floor(box[:2]).astype(int)
        fx2, fy2 = np.ceil(box[2:]).astype(int)
        face_crop = img[fy1:fy2, fx1:fx2]
        scale = min(1.0, 512 / max(face_crop.shape[:2]))
        if scale < 1:
            face_crop = cv2.resize(face_crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        ok, jpeg = cv2.imencode('.jpg', face_crop, [cv2.IMWRITE_JPEG_QUALITY, 90])
        if not ok:
            raise ApiError(503, "analysis_failed", "Could not save the face crop.", retryable=True)
        results.append(dict(
            bbox=dict(x=float(box[0] / w), y=float(box[1] / h),
                      w=float((box[2] - box[0]) / w), h=float((box[3] - box[1]) / h)),
            score=score, label="anime_face", manual=score == 0,
            face_px=float(max(box[2:] - box[:2])), embedding_model_id=MODEL_ID,
            embedding=base64.b64encode(vector.tobytes()).decode('ascii'),
            crop_jpeg=base64.b64encode(jpeg.tobytes()).decode('ascii'),
            outline=None, keypoints=None))
    return results
