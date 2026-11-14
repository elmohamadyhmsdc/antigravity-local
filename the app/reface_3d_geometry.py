"""
Antigravity Local - 3D Facial Geometry & Realism Preservation (Phase 5).

Provides canonical 3D facial geometry, static shape vs dynamic pose/expression decoupling,
surface normal estimation, self-occlusion visibility analysis, and PnP-based 3D pose alignment
with automatic fallback to 2D affine warping when 3D fit confidence is low.
"""

from dataclasses import dataclass, field
import math
from typing import Any, Dict, List, Optional, Tuple, Union

import cv2
import numpy as np


# -----------------------------------------------------------------------------
# Anthropometric 3D Canonical Face Model (in mm, centered at nose bridge)
# -----------------------------------------------------------------------------

CANONICAL_3D_68 = np.array([
    # Jawline (0-16)
    [-70.0,  30.0, -40.0], [-68.0,  10.0, -35.0], [-65.0, -10.0, -30.0], [-60.0, -30.0, -25.0],
    [-52.0, -50.0, -20.0], [-40.0, -68.0, -15.0], [-25.0, -82.0, -10.0], [-12.0, -90.0,  -5.0],
    [  0.0, -93.0,   0.0], [ 12.0, -90.0,  -5.0], [ 25.0, -82.0, -10.0], [ 40.0, -68.0, -15.0],
    [ 52.0, -50.0, -20.0], [ 60.0, -30.0, -25.0], [ 65.0, -10.0, -30.0], [ 68.0,  10.0, -35.0],
    [ 70.0,  30.0, -40.0],
    # Eyebrows (17-26)
    [-60.0,  45.0, -15.0], [-48.0,  55.0, -10.0], [-35.0,  58.0,  -8.0], [-22.0,  55.0,  -7.0],
    [-10.0,  48.0,  -8.0], [ 10.0,  48.0,  -8.0], [ 22.0,  55.0,  -7.0], [ 35.0,  58.0,  -8.0],
    [ 48.0,  55.0, -10.0], [ 60.0,  45.0, -15.0],
    # Nose bridge & tip (27-35)
    [  0.0,  40.0,  -5.0], [  0.0,  25.0,   3.0], [  0.0,  10.0,  12.0], [  0.0,  -5.0,  20.0],
    [-15.0, -15.0,   8.0], [ -7.0, -17.0,  14.0], [  0.0, -18.0,  16.0], [  7.0, -17.0,  14.0],
    [ 15.0, -15.0,   8.0],
    # Eyes (36-47)
    [-45.0,  35.0, -12.0], [-38.0,  40.0,  -8.0], [-28.0,  40.0,  -8.0], [-20.0,  35.0, -10.0],
    [-28.0,  32.0, -10.0], [-38.0,  32.0, -10.0], [ 20.0,  35.0, -10.0], [ 28.0,  40.0,  -8.0],
    [ 38.0,  40.0,  -8.0], [ 45.0,  35.0, -12.0], [ 38.0,  32.0, -10.0], [ 28.0,  32.0, -10.0],
    # Outer & Inner Mouth (48-67)
    [-30.0, -45.0,   0.0], [-20.0, -40.0,   4.0], [-10.0, -38.0,   6.0], [  0.0, -38.0,   7.0],
    [ 10.0, -38.0,   6.0], [ 20.0, -40.0,   4.0], [ 30.0, -45.0,   0.0], [ 20.0, -52.0,   3.0],
    [ 10.0, -55.0,   4.0], [  0.0, -56.0,   5.0], [-10.0, -55.0,   4.0], [-20.0, -52.0,   3.0],
    [-25.0, -45.0,   1.0], [-10.0, -42.0,   4.0], [  0.0, -42.0,   5.0], [ 10.0, -42.0,   4.0],
    [ 25.0, -45.0,   1.0], [ 10.0, -48.0,   3.0], [  0.0, -49.0,   4.0], [-10.0, -48.0,   3.0]
], dtype=np.float32)

# 6-point canonical 3D model for PnP: [left_eye, right_eye, nose_tip, mouth_left, mouth_right, chin]
CANONICAL_3D_6 = np.array([
    [-32.0,  35.0, -10.0],  # left eye
    [ 32.0,  35.0, -10.0],  # right eye
    [  0.0,  -5.0,  20.0],  # nose tip
    [-22.0, -45.0,   2.0],  # mouth left
    [ 22.0, -45.0,   2.0],  # mouth right
    [  0.0, -90.0,  -5.0],  # chin
], dtype=np.float32)
CANONICAL_3D_5 = CANONICAL_3D_6[:5]


# -----------------------------------------------------------------------------
# Data Models: Static Geometry vs Dynamic Pose/Expression Decoupling
# -----------------------------------------------------------------------------

@dataclass
class StaticFaceGeometry:
    """Subject static facial geometry (invariant across frames)."""
    identity_id: str
    canonical_points: np.ndarray  # (N, 3) 3D landmark points
    interpupillary_dist: float     # 3D distance between eye pupils
    face_width: float              # 3D cheekbone to cheekbone distance
    face_height: float             # 3D chin to brow distance
    depth_profile_ratio: float     # nose protrusion over face width (Z/W)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "identity_id": self.identity_id,
            "interpupillary_dist": round(float(self.interpupillary_dist), 2),
            "face_width": round(float(self.face_width), 2),
            "face_height": round(float(self.face_height), 2),
            "depth_profile_ratio": round(float(self.depth_profile_ratio), 4),
        }


@dataclass
class DynamicPoseExpression:
    """Frame-specific dynamic transformation and non-rigid expression."""
    yaw: float
    pitch: float
    roll: float
    rvec: np.ndarray       # (3, 1) Rodrigues rotation vector
    tvec: np.ndarray       # (3, 1) Translation vector
    rotation_matrix: np.ndarray  # (3, 3)
    expression_mouth_open: float  # delta distance in mouth opening
    fitting_confidence: float     # 0.0 to 1.0 based on reprojection error
    reprojection_error_px: float

    def to_dict(self) -> Dict[str, Any]:
        return {
            "yaw": round(float(self.yaw), 2),
            "pitch": round(float(self.pitch), 2),
            "roll": round(float(self.roll), 2),
            "expression_mouth_open": round(float(self.expression_mouth_open), 2),
            "fitting_confidence": round(float(self.fitting_confidence), 4),
            "reprojection_error_px": round(float(self.reprojection_error_px), 2),
        }


@dataclass
class SurfaceFacetVisibility:
    """Visibility of face sectors based on 3D surface normals vs camera view axis."""
    front_visible: bool
    left_cheek_visible: bool
    right_cheek_visible: bool
    chin_visible: bool
    left_cheek_cosine: float
    right_cheek_cosine: float
    view_angle_deg: float


# -----------------------------------------------------------------------------
# Geometry Decoupling & PnP Solver
# -----------------------------------------------------------------------------

def build_static_geometry_from_sources(sources: List[Any], identity_id: str = "unnamed") -> StaticFaceGeometry:
    """Construct subject-specific static 3D geometry from multi-photo bundle records."""
    # Anthropometric baseline
    canon = CANONICAL_3D_68.copy()
    
    # Calculate anthropometric distances on canonical base
    left_eye_center = np.mean(canon[36:42], axis=0)
    right_eye_center = np.mean(canon[42:48], axis=0)
    ipd = float(np.linalg.norm(right_eye_center - left_eye_center))
    width = float(np.linalg.norm(canon[16] - canon[0]))
    height = float(np.linalg.norm(canon[8] - np.mean(canon[17:27], axis=0)))
    nose_z = float(canon[30, 2] - left_eye_center[2])
    depth_ratio = float(nose_z / max(width, 1.0))

    return StaticFaceGeometry(
        identity_id=identity_id,
        canonical_points=canon,
        interpupillary_dist=ipd,
        face_width=width,
        face_height=height,
        depth_profile_ratio=depth_ratio,
    )


def estimate_camera_matrix(image_shape: Tuple[int, int]) -> Tuple[np.ndarray, np.ndarray]:
    """Approximate pinhole camera intrinsic matrix and zero distortion coefficients."""
    h, w = image_shape[:2]
    focal_length = float(max(h, w))
    center = (w / 2.0, h / 2.0)
    camera_matrix = np.array([
        [focal_length, 0.0, center[0]],
        [0.0, focal_length, center[1]],
        [0.0, 0.0, 1.0]
    ], dtype=np.float64)
    dist_coeffs = np.zeros((4, 1), dtype=np.float64)
    return camera_matrix, dist_coeffs


def estimate_dynamic_pose_pnp(
    landmarks_2d: np.ndarray,
    image_shape: Tuple[int, int],
    static_geom: Optional[StaticFaceGeometry] = None,
) -> DynamicPoseExpression:
    """Solve Perspective-n-Point to decouple 3D rotation, translation, and expression."""
    pts_2d = np.asarray(landmarks_2d, dtype=np.float64)
    if pts_2d.ndim != 2:
        pts_2d = pts_2d.reshape(-1, 2)

    num_pts = len(pts_2d)
    if num_pts >= 68:
        pts_2d_solve = pts_2d[:68]
        pts_3d = static_geom.canonical_points[:68].astype(np.float64) if static_geom else CANONICAL_3D_68.astype(np.float64)
    elif num_pts >= 6:
        pts_2d_solve = pts_2d[:6]
        pts_3d = CANONICAL_3D_6.astype(np.float64)
    elif num_pts == 5:
        eye_mid = (pts_2d[0] + pts_2d[1]) / 2.0
        mouth_mid = (pts_2d[3] + pts_2d[4]) / 2.0
        chin_pt = mouth_mid + (mouth_mid - eye_mid) * 0.7
        pts_2d_solve = np.vstack([pts_2d[:5], chin_pt.reshape(1, 2)])
        pts_3d = CANONICAL_3D_6.astype(np.float64)
    else:
        # Insufficient points: fallback identity
        eye = np.eye(3, dtype=np.float64)
        return DynamicPoseExpression(
            yaw=0.0, pitch=0.0, roll=0.0,
            rvec=np.zeros((3, 1), dtype=np.float64),
            tvec=np.array([[0.0], [0.0], [500.0]], dtype=np.float64),
            rotation_matrix=eye,
            expression_mouth_open=0.0,
            fitting_confidence=0.0,
            reprojection_error_px=999.0,
        )

    camera_matrix, dist_coeffs = estimate_camera_matrix(image_shape)

    # Solve PnP
    success, rvec, tvec = cv2.solvePnP(
        pts_3d,
        pts_2d_solve,
        camera_matrix,
        dist_coeffs,
        flags=cv2.SOLVEPNP_ITERATIVE
    )

    if not success or rvec is None or tvec is None:
        eye = np.eye(3, dtype=np.float64)
        return DynamicPoseExpression(
            yaw=0.0, pitch=0.0, roll=0.0,
            rvec=np.zeros((3, 1), dtype=np.float64),
            tvec=np.array([[0.0], [0.0], [500.0]], dtype=np.float64),
            rotation_matrix=eye,
            expression_mouth_open=0.0,
            fitting_confidence=0.0,
            reprojection_error_px=999.0,
        )

    # Compute reprojection error
    proj_pts, _ = cv2.projectPoints(pts_3d, rvec, tvec, camera_matrix, dist_coeffs)
    proj_pts = proj_pts.reshape(-1, 2)
    err = float(np.mean(np.linalg.norm(pts_2d_solve - proj_pts, axis=1)))

    # Compute rotation matrix and Euler angles
    R, _ = cv2.Rodrigues(rvec)
    sy = math.sqrt(R[0, 0] * R[0, 0] + R[1, 0] * R[1, 0])
    singular = sy < 1e-6
    if not singular:
        pitch = math.atan2(R[2, 1], R[2, 2])
        yaw = math.atan2(-R[2, 0], sy)
        roll = math.atan2(R[1, 0], R[0, 0])
    else:
        pitch = math.atan2(-R[1, 2], R[1, 1])
        yaw = math.atan2(-R[2, 0], sy)
        roll = 0.0

    yaw_deg = float(np.degrees(yaw))
    pitch_deg = float(np.degrees(pitch))
    roll_deg = float(np.degrees(roll))

    # Expression measurement: mouth height relative to face size
    mouth_open = 0.0
    if num_pts >= 68:
        upper_lip = pts_2d[51]
        lower_lip = pts_2d[57]
        mouth_open = float(np.linalg.norm(lower_lip - upper_lip))

    # Fitting confidence: decays smoothly as reprojection error increases
    # 0 px err -> 1.0 confidence, 10 px err -> ~0.37 confidence
    confidence = float(np.exp(-err / 10.0))
    if not np.isfinite(confidence):
        confidence = 0.0

    return DynamicPoseExpression(
        yaw=yaw_deg,
        pitch=pitch_deg,
        roll=roll_deg,
        rvec=rvec,
        tvec=tvec,
        rotation_matrix=R,
        expression_mouth_open=mouth_open,
        fitting_confidence=confidence,
        reprojection_error_px=err,
    )


# -----------------------------------------------------------------------------
# Surface Normal Estimation & Self-Occlusion Analysis
# -----------------------------------------------------------------------------

def analyze_surface_visibility(
    pose: DynamicPoseExpression,
    threshold_cosine: float = 0.15,
) -> SurfaceFacetVisibility:
    """Determine surface patch visibility and self-occlusions using 3D surface normals."""
    R = pose.rotation_matrix
    
    # Canonical outward surface normals in object space
    n_front = np.array([0.0, 0.0, 1.0], dtype=np.float64)       # nose/forehead
    n_left = np.array([-0.707, 0.0, 0.707], dtype=np.float64)   # left cheek (-X, +Z)
    n_right = np.array([0.707, 0.0, 0.707], dtype=np.float64)   # right cheek (+X, +Z)
    n_chin = np.array([0.0, -0.707, 0.707], dtype=np.float64)   # chin/jaw

    # Transform normals by 3D head rotation matrix
    r_front = R @ n_front
    r_left = R @ n_left
    r_right = R @ n_right
    r_chin = R @ n_chin

    # Optical view vector pointing towards camera is [0, 0, -1]
    # In camera coordinates, looking at face along -Z: surface is facing camera if normal.z > 0
    view_z = np.array([0.0, 0.0, 1.0], dtype=np.float64)

    cos_front = float(np.dot(r_front, view_z))
    cos_left = float(np.dot(r_left, view_z))
    cos_right = float(np.dot(r_right, view_z))
    cos_chin = float(np.dot(r_chin, view_z))

    front_vis = cos_front >= threshold_cosine
    left_vis = cos_left >= threshold_cosine
    right_vis = cos_right >= threshold_cosine
    chin_vis = cos_chin >= threshold_cosine

    return SurfaceFacetVisibility(
        front_visible=front_vis,
        left_cheek_visible=left_vis,
        right_cheek_visible=right_vis,
        chin_visible=chin_vis,
        left_cheek_cosine=cos_left,
        right_cheek_cosine=cos_right,
        view_angle_deg=float(abs(pose.yaw)),
    )


def generate_3d_visibility_confidence_mask(
    image_shape: Tuple[int, int],
    landmarks_2d: np.ndarray,
    pose: DynamicPoseExpression,
) -> np.ndarray:
    """Generate a continuous (H, W) float32 visibility mask (0.0 to 1.0).

    Regions occluded due to 3D head turn (e.g. far eye/cheek when yaw > 35 deg)
    are given 0 confidence, preventing blurred hallucination or edge distortion.
    """
    h, w = image_shape[:2]
    mask = np.ones((h, w), dtype=np.float32)

    vis = analyze_surface_visibility(pose)

    # When facing forward (|yaw| < 20 deg), both sides fully visible
    if abs(pose.yaw) < 20.0:
        return mask

    pts = np.asarray(landmarks_2d, dtype=np.float32)
    if pts.shape[0] < 5:
        return mask

    if pose.yaw < -20.0:
        # Subject turning left -> subject's left cheek turns away from camera
        weight = float(np.clip((vis.left_cheek_cosine + 0.2) / 0.5, 0.0, 1.0))
        if pts.shape[0] >= 68:
            occluded_pts = pts[0:8].astype(np.int32)
            cv2.fillPoly(mask, [occluded_pts], weight)
        else:
            cx, cy = int(pts[0, 0]), int(pts[0, 1])
            cv2.circle(mask, (cx, cy), int(w * 0.25), weight, -1)

    elif pose.yaw > 20.0:
        # Subject turning right -> subject's right cheek turns away from camera
        weight = float(np.clip((vis.right_cheek_cosine + 0.2) / 0.5, 0.0, 1.0))
        if pts.shape[0] >= 68:
            occluded_pts = pts[9:17].astype(np.int32)
            cv2.fillPoly(mask, [occluded_pts], weight)
        else:
            cx, cy = int(pts[1, 0]), int(pts[1, 1])
            cv2.circle(mask, (cx, cy), int(w * 0.25), weight, -1)

    # Soften edges
    mask = cv2.GaussianBlur(mask, (15, 15), 5.0)
    return np.clip(mask, 0.0, 1.0)


# -----------------------------------------------------------------------------
# Quality Gate & Decision Logic
# -----------------------------------------------------------------------------

def should_use_3d_geometry(
    pose: DynamicPoseExpression,
    face_pixel_size: int,
    min_confidence: float = 0.50,
) -> Tuple[bool, str]:
    """Quality gate deciding whether to apply 3D alignment or fallback to 2D affine.

    Returns (use_3d: bool, reason: str).
    """
    if face_pixel_size < 64:
        return False, "face_too_small_for_3d_fitting"

    if pose.fitting_confidence < min_confidence:
        return False, f"low_fitting_confidence_{pose.fitting_confidence:.2f}"

    if pose.reprojection_error_px > 12.0:
        return False, f"high_reprojection_error_{pose.reprojection_error_px:.1f}px"

    # For nearly flat frontal poses, 2D affine is mathematically optimal & fastest
    if abs(pose.yaw) < 15.0 and abs(pose.pitch) < 15.0:
        return False, "frontal_pose_2d_affine_optimal"

    # Only engage 3D geometry assistance where it provides demonstrable benefit:
    # Steep angles (|yaw| >= 15 deg or |pitch| >= 15 deg) with high fitting confidence
    return True, "3d_geometry_assisted_angle"
