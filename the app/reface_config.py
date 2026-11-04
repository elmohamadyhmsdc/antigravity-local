"""Model-free configuration for the single public Reface pipeline."""

QUALITY_PROFILES = ("fast", "balanced", "detail")
RESTORER_ORDER = ("codeformer", "gfpgan_1.4", "gpen_bfr_512", "gpen_bfr_1024", "restoreformer_plus_plus")


def profile_defaults(profile, available):
    if profile not in QUALITY_PROFILES:
        raise ValueError("Choose fast, balanced or detail quality.")
    preferences = ("gpen_bfr_1024", "gpen_bfr_512") if profile == "detail" else ("gpen_bfr_512",)
    fallback = next((name for name in RESTORER_ORDER if name in available), "none")
    restorer = "none" if profile == "fast" else next((name for name in preferences if name in available), fallback)
    return dict(restorer=restorer, restore_size=1024 if restorer == "gpen_bfr_1024" else 512,
                use_parser=profile != "fast")


# Typical cost of swapping ONE normal-size face (about 240 px tall in a 720p frame), in milliseconds, so the
# phone can say "about 4 min" before anything is queued. Measured 2026-11-04 on the RTX 4050 Laptop (6 GB) with
# the default hyperswap + GPEN models: a photo is one frame run alone; a video overlaps each frame's GPU work with
# the previous frame's compositing (reface_engine_v3._stage_frame), which is why it is cheaper per face.
# Faces much smaller or larger, other GPUs and extra faces in a frame move these; treat them as typical, not exact.
TYPICAL_MS_PER_FACE = {
    "photo": {"fast": 140, "balanced": 300, "detail": 660},
    "video": {"fast": 90, "balanced": 255, "detail": 415},
}


def profile_catalog(available):
    """Automatic settings per quality profile plus the typical cost of one face for it (photo and video)."""
    return {name: {**profile_defaults(name, available),
                   "photo_ms_per_face": TYPICAL_MS_PER_FACE["photo"][name],
                   "video_ms_per_face": TYPICAL_MS_PER_FACE["video"][name]}
            for name in QUALITY_PROFILES}
