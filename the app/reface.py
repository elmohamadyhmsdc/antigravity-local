"""One public Reface engine for new photo and video work.

The shared pipeline inherits source/face-set handling, uses identity-aware video
tracking and current-frame recovery, and restores/blends only the face region.
Quality profiles configure this same pipeline; they never select a legacy engine.
"""
from contextlib import contextmanager

from face_restore import MODELS_DIR, RESTORER_FILES
from reface_config import output_defaults, profile_defaults
from reface_engine import FaceData, Faceset, RefaceResult
from reface_engine_v3 import RefaceEngineV3


@contextmanager
def managed_reface_engine(**options):
    engine = RefaceEngine(**options)
    try:
        yield engine
    finally:
        unload = getattr(engine, "unload", None)
        if unload is not None:
            try:
                unload()
            except Exception as error:
                import logging

                logging.getLogger(__name__).warning("Reface cleanup failed: %s", error)


def faceset_from_bundle(bundle, name=None):
    """Use the same validated, pose-aware profile for a local or API request."""
    import numpy as np

    from identity_bundle import IdentityBundle

    if isinstance(bundle, dict):
        bundle = IdentityBundle.from_dict(bundle)
    if not bundle.sources:
        raise ValueError("The identity profile has no usable source faces.")
    faceset = Faceset(name or bundle.label)
    faceset.identity_bundle = bundle
    for source in bundle.sources:
        pose = source.pose or {}
        faceset.add_face(FaceData(
            "", np.asarray(source.embedding, np.float32),
            tuple(pose.get(axis) or 0.0 for axis in ("yaw", "pitch", "roll")), [], source.quality,
            generated=source.is_synthetic,
        ))
    return faceset


def merge_video_diagnostics(summary, segment):
    """Keep the gap count and a bounded list for a resumable render."""
    if not segment:
        return summary
    summary = summary or dict(gaps=[], gap_count=0, truncated_log=False)
    summary["gap_count"] += segment["gap_count"]
    summary["gaps"].extend(segment["gaps"][: max(0, 30 - len(summary["gaps"]))])
    summary["truncated_log"] |= segment["truncated_log"] or summary["gap_count"] > len(summary["gaps"])
    summary["gap_basis"] = segment["gap_basis"]
    return summary


class RefaceEngine(RefaceEngineV3):
    VERSION = "unified"
    def __init__(self, *, quality_profile="balanced", restorer="auto", use_parser=None, **kwargs):
        available = [name for name, filename in RESTORER_FILES.items() if (MODELS_DIR / filename).is_file()]
        settings = profile_defaults(quality_profile, available)
        self.quality_profile = quality_profile
        selected = settings["restorer"] if restorer in (None, "auto") else restorer
        if kwargs.get("dfm_path"):
            selected = "none"
        kwargs.setdefault("restore_size", 1024 if selected == "gpen_bfr_1024" else 512)
        finishing = output_defaults(quality_profile)
        for option in ("video_crf", "video_preset"):
            kwargs.setdefault(option, finishing[option])
        overrides = dict(kwargs.pop("realism_overrides", None) or {})
        overrides.setdefault("focus_match_strength", finishing["focus_match_strength"])
        kwargs["realism_overrides"] = overrides
        # Every profile uses the measured best swapper ("auto" -> SWAPPER_PREFERENCE). 1c for
        # "detail" was re-measured on 2026-10-31: lower identity than 1b, slower, no sharper.
        super().__init__(restorer=selected,
                         use_parser=settings["use_parser"] if use_parser is None else use_parser, **kwargs)

    def reface_image(self, target_image_path, faceset, target_face_indices=None,
                     target_face_embeddings=None, **kwargs):
        result = self.reface_image_v3(target_image_path, faceset, target_face_indices,
                                      target_face_embeddings, **kwargs)
        result.message = result.message.replace("V3", "Reface")
        return result

    def reface_video(self, target_video_path, faceset, **kwargs):
        kwargs.setdefault("enable_diagnostics", True)
        result = self.reface_video_v3(target_video_path, faceset, **kwargs)
        result.message = result.message.replace("V3", "Reface")
        if result.success:
            gaps = (result.details or {}).get("diagnostics", {}).get("gap_count", 0)
            if gaps:
                result.details.setdefault("warnings", []).append(
                    "Some video frames may contain an unchanged face. Review the result.")
        return result

    def effective_settings(self):
        return {**super().effective_settings(), "engine": "reface", "quality_profile": self.quality_profile}
