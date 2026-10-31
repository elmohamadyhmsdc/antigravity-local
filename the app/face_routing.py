"""Face routing and baby-face veto logic.

Decides whether a detection is a real human face (People) or an anime/cartoon character
(Characters), implementing containment-aware overlap veto to prevent real infants/babies
from leaking into Characters.
"""
from __future__ import annotations

from typing import List, Dict, Any, Tuple, Union

IOU_THRESH = 0.50
CONTAINMENT_THRESH = 0.60
DEFAULT_REAL_SCAN_THRESH = 0.70
DEFAULT_REAL_VETO_THRESH = 0.40


def _get_bbox(det: Union[Dict[str, Any], Any]) -> List[float]:
    """Helper to get [x1, y1, x2, y2] from either a dict or an object with bbox/bbox_norm."""
    if isinstance(det, dict):
        return [float(x) for x in det["bbox"]]
    if hasattr(det, "bbox"):
        return [float(x) for x in det.bbox]
    raise ValueError(f"Cannot extract bbox from {det}")


def _get_score(det: Union[Dict[str, Any], Any]) -> float:
    """Helper to get score/det_score from either a dict or an object."""
    if isinstance(det, dict):
        return float(det.get("score", det.get("det_score", 1.0)))
    if hasattr(det, "det_score"):
        return float(det.det_score)
    if hasattr(det, "score"):
        return float(det.score)
    return 1.0


def box_iou(b1: List[float], b2: List[float]) -> float:
    """Compute Intersection over Union (IoU) of two [x1, y1, x2, y2] boxes."""
    ix1 = max(b1[0], b2[0])
    iy1 = max(b1[1], b2[1])
    ix2 = min(b1[2], b2[2])
    iy2 = min(b1[3], b2[3])

    iw = max(0.0, ix2 - ix1)
    ih = max(0.0, iy2 - iy1)
    inter = iw * ih
    if inter <= 0.0:
        return 0.0

    area1 = max(0.0, b1[2] - b1[0]) * max(0.0, b1[3] - b1[1])
    area2 = max(0.0, b2[2] - b2[0]) * max(0.0, b2[3] - b2[1])
    union = area1 + area2 - inter
    return inter / union if union > 0.0 else 0.0


def box_containment(b1: List[float], b2: List[float]) -> float:
    """Compute maximum containment ratio: inter / min(area1, area2)."""
    ix1 = max(b1[0], b2[0])
    iy1 = max(b1[1], b2[1])
    ix2 = min(b1[2], b2[2])
    iy2 = min(b1[3], b2[3])

    iw = max(0.0, ix2 - ix1)
    ih = max(0.0, iy2 - iy1)
    inter = iw * ih
    if inter <= 0.0:
        return 0.0

    area1 = max(0.0, b1[2] - b1[0]) * max(0.0, b1[3] - b1[1])
    area2 = max(0.0, b2[2] - b2[0]) * max(0.0, b2[3] - b2[1])
    min_area = min(area1, area2)
    return inter / min_area if min_area > 0.0 else 0.0


def overlaps_real_face(
    real_box: List[float],
    anime_box: List[float],
    iou_thresh: float = IOU_THRESH,
    containment_thresh: float = CONTAINMENT_THRESH,
) -> bool:
    """Check if real and anime boxes describe the same face via IoU or Containment."""
    iou = box_iou(real_box, anime_box)
    if iou >= iou_thresh:
        return True
    contain = box_containment(real_box, anime_box)
    return contain >= containment_thresh


def route_detections(
    real_dets: List[Any],
    anime_dets: List[Any],
    real_scan_thresh: float = DEFAULT_REAL_SCAN_THRESH,
    real_veto_thresh: float = DEFAULT_REAL_VETO_THRESH,
) -> Tuple[List[Any], List[Any]]:
    """Route detections between real human faces and anime character faces.

    Args:
        real_dets: SCRFD detections (each having bbox and score).
        anime_dets: AnimeFaceDetector detections (each having bbox and score).
        real_scan_thresh: minimum score for a real face to be routed to People.
        real_veto_thresh: minimum score for a real face to veto an overlapping anime detection.

    Returns:
        (routed_real, routed_anime)
    """
    # Candidate real faces that pass the scan threshold for admission to People
    people_faces = [d for d in real_dets if _get_score(d) >= real_scan_thresh]

    # Real faces at or above veto threshold used to veto false anime detections
    veto_faces = [d for d in real_dets if _get_score(d) >= real_veto_thresh]
    veto_boxes = [_get_bbox(d) for d in veto_faces]

    surviving_anime = []
    for ad in anime_dets:
        abox = _get_bbox(ad)
        # If any real face (at veto threshold) overlaps with this anime detection, veto it
        is_vetoed = any(overlaps_real_face(rbox, abox) for rbox in veto_boxes)
        if not is_vetoed:
            surviving_anime.append(ad)

    return people_faces, surviving_anime
