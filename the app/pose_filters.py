"""
Pose rules and descriptor in Python - the SAME rules as mobile/lib/domain/pose/{pose_geometry,pose_rules,
pose_descriptor}.dart (roadmap sections 2 and 3), used only by the Phase 0 evaluation (`eval_pose_filters.py`).
Parity is held by the shared golden cases in mobile_api/contract/fixtures/pose/cases.json, checked by
`test_pose_filters.py` here and by `mobile/test/domain/pose_cases_test.dart` on the phone.

Pure numpy; no models, files or database.
"""

import json
import math
from typing import Dict, List, Optional, Set, Tuple

import numpy as np

KPT_VISIBLE = 0.3
MIRROR = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15]
MIN_SHARED = 8
DEFAULT_SIGMA = 0.22
L_EYE, R_EYE, L_EAR, R_EAR = 1, 2, 3, 4
L_SH, R_SH, L_EL, R_EL, L_WR, R_WR = 5, 6, 7, 8, 9, 10
L_HIP, R_HIP, L_KN, R_KN, L_AN, R_AN = 11, 12, 13, 14, 15, 16
LEGS = ((L_HIP, L_KN, L_AN), (R_HIP, R_KN, R_AN))


class Pose:
    """`points`: 17 x [x, y, score] in IMAGE PIXELS (kpts are normalised by width and height separately
    on the phone: denormalise first, see `from_normalised`)."""

    def __init__(self, points, extent: Optional[str] = None, face_yaw: Optional[float] = None):
        self.p = np.asarray(points, dtype=np.float64).reshape(17, 3)
        self.extent, self.face_yaw = extent, face_yaw

    @classmethod
    def from_normalised(cls, kpts_json, width, height, extent=None, face_yaw=None) -> Optional["Pose"]:
        if not kpts_json or not width or not height:
            return None
        try:
            raw = np.asarray(json.loads(kpts_json) if isinstance(kpts_json, str) else kpts_json, dtype=np.float64)
        except ValueError:
            return None
        if raw.shape != (17, 3):
            return None
        raw[:, 0] *= width
        raw[:, 1] *= height
        return cls(raw, extent, face_yaw)

    def has(self, ids) -> bool:
        return all(np.isfinite(self.p[i]).all() and self.p[i, 2] >= KPT_VISIBLE for i in ids)

    def xy(self, i):
        return self.p[i, :2]

    @property
    def visible_count(self) -> int:
        return int((self.p[:, 2] >= KPT_VISIBLE).sum())

    def mid(self, a, b):
        return (self.xy(a) + self.xy(b)) / 2

    @property
    def has_shoulders(self):
        return self.has((L_SH, R_SH))

    @property
    def has_hips(self):
        return self.has((L_HIP, R_HIP))

    @property
    def torso(self) -> Optional[float]:
        if not (self.has_shoulders and self.has_hips):
            return None
        return float(np.linalg.norm(self.mid(L_SH, R_SH) - self.mid(L_HIP, R_HIP)))

    @property
    def shoulder_width(self) -> Optional[float]:
        return float(np.linalg.norm(self.xy(L_SH) - self.xy(R_SH))) if self.has_shoulders else None

    @property
    def spine_tilt(self) -> Optional[float]:
        if not (self.has_shoulders and self.has_hips):
            return None
        d = np.abs(self.mid(L_SH, R_SH) - self.mid(L_HIP, R_HIP))
        return math.degrees(math.atan2(d[0], d[1]))

    @property
    def legs_possible(self):
        return self.extent in ("full", "knee")

    @property
    def ankles_possible(self):
        return self.extent == "full"


def angle(a, b, c) -> float:
    v1, v2 = np.asarray(a) - np.asarray(b), np.asarray(c) - np.asarray(b)
    n = np.linalg.norm(v1) * np.linalg.norm(v2)
    if n == 0:
        return 0.0
    return math.degrees(math.acos(float(np.clip(v1 @ v2 / n, -1, 1))))


def _dist(a, b) -> float:
    return float(np.linalg.norm(np.asarray(a) - np.asarray(b)))


def is_standing(p: Pose) -> bool:
    if not p.ankles_possible:
        return False
    tilt = p.spine_tilt
    if tilt is None or tilt >= 25:
        return False
    for hip, knee, ankle in LEGS:
        if not p.has((hip, knee, ankle)):
            return False
        h, k, a = p.xy(hip), p.xy(knee), p.xy(ankle)
        if angle(h, k, a) <= 155 or not (h[1] < k[1] < a[1]) or _dist(h, k) < 0.7 * _dist(k, a):
            return False
    return True


def is_sitting(p: Pose) -> bool:
    if not p.legs_possible:
        return False
    tilt, torso = p.spine_tilt, p.torso
    if tilt is None or torso is None or tilt >= 35:
        return False
    for hip, knee, ankle in LEGS:
        if not p.has((hip, knee, ankle)):
            continue
        h, k, a = p.xy(hip), p.xy(knee), p.xy(ankle)
        bend = angle(h, k, a)
        side = 70 <= bend <= 135 and abs(h[1] - k[1]) < 0.35 * torso
        frontal = _dist(h, k) < 0.6 * _dist(k, a) and k[1] > h[1]
        if side or frontal:
            return not is_standing(p)
    return False


def _standing_after_rotation(p: Pose) -> bool:
    for turn in (1.0, -1.0):
        pts = p.p.copy()
        pts[:, 0], pts[:, 1] = -turn * p.p[:, 1], turn * p.p[:, 0]
        if is_standing(Pose(pts, p.extent)):
            return True
    return False


def is_lying(p: Pose, guard_rotated_standing: bool = False) -> bool:
    tilt = p.spine_tilt
    if tilt is None or tilt <= 60:
        return False
    return not (guard_rotated_standing and _standing_after_rotation(p))


def _raised(p: Pose, torso: float) -> Tuple[Optional[bool], Optional[bool]]:
    def side(sh, wr):
        return None if not p.has((sh, wr)) else bool(p.xy(wr)[1] < p.xy(sh)[1] - 0.25 * torso)
    return side(L_SH, L_WR), side(R_SH, R_WR)


def _arms_spread(p: Pose, torso: float) -> bool:
    if not p.has((L_SH, R_SH, L_EL, R_EL, L_WR, R_WR)):
        return False
    for s, e, w in ((L_SH, L_EL, L_WR), (R_SH, R_EL, R_WR)):
        if abs(p.xy(w)[1] - p.xy(s)[1]) > 0.25 * torso or angle(p.xy(s), p.xy(e), p.xy(w)) <= 150:
            return False
    return _dist(p.xy(L_WR), p.xy(R_WR)) > 2.2 * p.shoulder_width


def _hands_on_hips(p: Pose, torso: float) -> bool:
    if not p.has((L_SH, R_SH, L_EL, R_EL, L_WR, R_WR, L_HIP, R_HIP)):
        return False
    top, bottom = p.mid(L_SH, R_SH), p.mid(L_HIP, R_HIP)
    d = bottom - top
    length = float(np.linalg.norm(d))

    def from_midline(q):
        return 0.0 if length == 0 else abs((q[0] - top[0]) * d[1] - (q[1] - top[1]) * d[0]) / length

    for s, e, w, h in ((L_SH, L_EL, L_WR, L_HIP), (R_SH, R_EL, R_WR, R_HIP)):
        if _dist(p.xy(w), p.xy(h)) > 0.3 * torso or angle(p.xy(s), p.xy(e), p.xy(w)) >= 120:
            return False
        if from_midline(p.xy(e)) <= from_midline(p.xy(s)):
            return False
    return True


def is_frontal(p: Pose) -> bool:
    torso, span = p.torso, p.shoulder_width
    if torso is None or span is None or span < 0.6 * torso:
        return False
    if p.face_yaw is not None:
        return abs(p.face_yaw) < 25
    return p.has((L_EYE, R_EYE, L_EAR, R_EAR))


def is_profile(p: Pose) -> bool:
    if p.face_yaw is not None and abs(p.face_yaw) > 60:
        return True
    torso, span = p.torso, p.shoulder_width
    if torso is None or span is None:
        return False
    ears = int(p.p[L_EAR, 2] >= KPT_VISIBLE) + int(p.p[R_EAR, 2] >= KPT_VISIBLE)
    return ears == 1 and span < 0.35 * torso


def is_back(p: Pose) -> bool:
    if p.face_yaw is not None or not p.has_shoulders:
        return False
    return all(p.p[i, 2] < 0.2 for i in (0, L_EYE, R_EYE))


TIER_A = ("lying", "standing", "sitting", "arms_up", "one_arm_up", "arms_spread", "hands_on_hips",
          "frontal", "profile", "back")


def tier_a_tags(p: Pose, guard_rotated_standing: bool = False) -> Set[str]:
    tags = set()
    if is_lying(p, guard_rotated_standing):
        tags.add("lying")
    if is_standing(p):
        tags.add("standing")
    if is_sitting(p):
        tags.add("sitting")
    if p.spine_tilt is not None and 25 <= p.spine_tilt <= 60:
        tags.add("bent")
    torso = p.torso
    if torso is not None:
        left, right = _raised(p, torso)
        if left is True and right is True:
            tags.add("arms_up")
        if (left is True and right is False) or (left is False and right is True):
            tags.add("one_arm_up")
        if _arms_spread(p, torso):
            tags.add("arms_spread")
        if _hands_on_hips(p, torso):
            tags.add("hands_on_hips")
    # Orientation to the camera is not asked of a body lying across the frame (decision: roadmap 3.4 is silent).
    tilt = p.spine_tilt
    if tilt is None or tilt <= 60:
        if is_frontal(p):
            tags.add("frontal")
        if is_profile(p):
            tags.add("profile")
        if is_back(p):
            tags.add("back")
    return tags


# --- descriptor ---------------------------------------------------------------------------------------

class Feature:
    def __init__(self, data: np.ndarray, mask: int, scale_source: str):
        self.data, self.mask, self.scale_source = data, mask, scale_source

    @property
    def count(self) -> int:
        return bin(self.mask).count("1")


def build_feature(p: Pose) -> Optional[Feature]:
    if not np.isfinite(p.p).all():
        return None
    torso = p.torso
    if torso is not None and torso > 1:
        origin, scale, source = p.mid(L_HIP, R_HIP), torso, "torso"
    elif (p.has_shoulders and p.has((L_EYE, R_EYE, L_EAR, R_EAR))
          and (p.face_yaw is None or abs(p.face_yaw) < 25)):
        width = p.shoulder_width
        if width <= 1:
            return None
        origin, scale, source = p.mid(L_SH, R_SH), width * 1.35, "shoulder"
    else:
        return None
    data, mask = np.zeros(34, dtype=np.float32), 0
    for i in range(17):
        if p.p[i, 2] < KPT_VISIBLE:
            continue
        mask |= 1 << i
        data[2 * i], data[2 * i + 1] = (p.p[i, :2] - origin) / scale
    feature = Feature(data, mask, source)
    return feature if feature.count >= MIN_SHARED else None


def mirror_feature(f: Feature) -> Feature:
    data, mask = np.zeros(34, dtype=np.float32), 0
    for i in range(17):
        j = MIRROR[i]
        data[2 * j], data[2 * j + 1] = -f.data[2 * i], f.data[2 * i + 1]
        if f.mask & (1 << i):
            mask |= 1 << j
    return Feature(data, mask, f.scale_source)


def _compare(a: Feature, b: Feature, sigma: float):
    both = a.mask & b.mask
    shared = bin(both).count("1")
    if shared < MIN_SHARED:
        return None
    errors = {}
    total = weight = 0.0
    for i in range(17):
        if not both & (1 << i):
            continue
        dx = float(a.data[2 * i]) - float(b.data[2 * i])
        dy = float(a.data[2 * i + 1]) - float(b.data[2 * i + 1])
        errors[i] = dx * dx + dy * dy
        w = 0.25 if i < L_SH else 1.0
        total += errors[i] * w
        weight += w
    worst = 0.0
    for region in ((5, 7, 9), (6, 8, 10), (11, 13, 15), (12, 14, 16), (5, 6, 11, 12)):
        visible = [errors[i] for i in region if i in errors]
        if len(visible) >= 2:
            worst = max(worst, sum(visible) / len(visible))
    squared_error = 0.45 * total / weight + 0.55 * worst
    return math.exp(-squared_error / (2 * sigma * sigma)), shared / (a.mask | b.mask).bit_count(), shared



def compare(a: Feature, b: Feature, sigma: float = DEFAULT_SIGMA):
    """(similarity, coverage, shared) or None when not comparable; the best of straight / mirrored."""
    def valid(f):
        return (f.data.shape == (34,) and np.isfinite(f.data).all()
                and 0 < f.mask < (1 << 17) and f.count >= MIN_SHARED)
    if (a.scale_source != b.scale_source or not valid(a) or not valid(b)
            or not math.isfinite(sigma) or sigma <= 0):
        return None
    straight, flipped = _compare(a, b, sigma), _compare(a, mirror_feature(b), sigma)
    if straight is None:
        return flipped
    if flipped is None:
        return straight
    return flipped if flipped[0] * flipped[1] > straight[0] * straight[1] else straight
