"""One public Reface engine for new photo and video work.

The shared pipeline inherits source/face-set handling, uses identity-aware video
tracking and current-frame recovery, and restores/blends only the face region.
Quality profiles configure this same pipeline; they never select a legacy engine.
"""
from face_restore import MODELS_DIR, RESTORER_FILES
from reface_config import profile_defaults
from reface_engine import FaceData, Faceset, RefaceResult
from reface_engine_v3 import RefaceEngineV3


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
        super().__init__(restorer=selected,
                         use_parser=settings["use_parser"] if use_parser is None else use_parser, **kwargs)

    def reface_image(self, target_image_path, faceset, target_face_indices=None,
                     target_face_embeddings=None, **kwargs):
        result = self.reface_image_v3(target_image_path, faceset, target_face_indices,
                                      target_face_embeddings, **kwargs)
        result.message = result.message.replace("V3", "Reface")
        return result

    def reface_video(self, target_video_path, faceset, **kwargs):
        result = self.reface_video_v3(target_video_path, faceset, **kwargs)
        result.message = result.message.replace("V3", "Reface")
        return result

    def effective_settings(self):
        return {**super().effective_settings(), "engine": "reface", "quality_profile": self.quality_profile}
