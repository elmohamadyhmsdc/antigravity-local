"""Desktop controls and adapters for the public Reface pipeline.

Importing this module does not read the gallery, jobs, or load inference models.
"""
from pathlib import Path

from reface_config import QUALITY_PROFILES, profile_defaults


PROFILE_LABELS = {"fast": "Fast", "balanced": "Balanced", "detail": "More detail"}
PROFILE_HELP = {
    "fast": "Skips automatic restoration and parser blending to reduce processing work. Every video frame is still processed.",
    "balanced": "Adds face restoration and parser blending when the installed models support them.",
    "detail": "Prefers a larger restoration crop when available. Adds processing work; extra detail can change the likeness.",
}
RESTORER_HELP = {
    "none": "Off: keeps the face swap without a separate restoration pass. Less processing work.",
    "codeformer": "CodeFormer: adjustable balance between restoring detail and staying faithful to the swapped face.",
    "gfpgan_1.4": "GFPGAN 1.4: restores facial detail. Added detail can change texture or likeness.",
    "gpen_bfr_512": "GPEN 512: restores a 512-pixel face crop with less processing work than GPEN 1024.",
    "gpen_bfr_1024": "GPEN 1024: restores a larger face crop for close-ups; requires more processing work than GPEN 512.",
    "restoreformer_plus_plus": "RestoreFormer++: an alternative restoration model. Compare detail and likeness using a preview.",
}


def render_options(st, faceset_name=None):
    """Return the exact constructor options used by foreground and queued swaps."""
    from face_restore import MODELS_DIR, RESTORER_FILES
    from face_swappers import available_swappers
    from reface_engine_v3 import DEFAULT_IDENTITY_BOOST

    dfm_path = None
    if faceset_name:
        from dfl_bridge import dfm_for
        candidate = dfm_for(faceset_name)
        if candidate and st.checkbox(
            f"Use the trained video model for {faceset_name}", value=True, key="reface_use_dfm",
            help="Uses this person's trained DeepFaceLab export as the identity source.",
        ):
            dfm_path = str(candidate)

    available = [name for name, filename in RESTORER_FILES.items() if (MODELS_DIR / filename).is_file()]
    if dfm_path:
        profile, restorer, use_parser = "balanced", "none", True
        st.caption("Trained identity: separate face restoration is disabled.")
        weight = 0.5
    else:
        profile = st.selectbox("Quality", QUALITY_PROFILES, index=1, key="reface_quality_profile",
                               format_func=PROFILE_LABELS.get)
        st.caption(PROFILE_HELP[profile])
        defaults = profile_defaults(profile, available)
        restorer = st.selectbox("Restorer", ["auto", "none"] + available, key="reface_restorer",
                                format_func=lambda name: "Automatic" if name == "auto" else name)
        actual_restorer = defaults["restorer"] if restorer == "auto" else restorer
        if restorer == "auto":
            st.caption(f"Automatic starts with {actual_restorer} for {PROFILE_LABELS[profile]}. "
                       "It uses the models installed on this computer.")
        st.caption(RESTORER_HELP.get(actual_restorer, actual_restorer))
        st.caption("512 / 1024 is the restored face crop size; it does not change the video resolution. "
                   "Processing speed depends on the GPU, face count and source resolution.")
        weight = st.slider("CodeFormer fidelity", 0.0, 1.0, 0.5, 0.05, key="reface_fidelity",
                           help="Higher stays closer to the swapped face; lower adds stronger restoration.") if actual_restorer == "codeformer" else 0.5
        use_parser = st.checkbox("Parser blending", value=defaults["use_parser"],
                                 key=f"reface_parser_{profile}", help="Blends the hairline and jaw using a face-region mask.")

    use_occluder = st.checkbox("Occlusion handling", value=True, key="reface_occluder",
                               help="Preserves hands and objects in front of the face.")
    with st.expander("Advanced face options"):
        swappers = available_swappers()
        swapper = st.selectbox("Swapper model", ["auto"] + swappers, key="reface_swapper",
                               help="Automatic uses the installed-model evaluation, when available.")
        boost = st.slider("Identity strength", 0.0, 1.0, float(DEFAULT_IDENTITY_BOOST), 0.05,
                          key="reface_identity_strength", help="Higher strengthens the source identity; too high can look exaggerated.")
        preset = st.selectbox("Appearance", ["natural", "maximum_detail", "clean"], key="reface_appearance",
                               format_func=lambda value: {"natural": "Natural", "maximum_detail": "Maximum detail", "clean": "Clean"}[value])
        overrides = {}
        if st.checkbox("Fine-tune realism", key="reface_tune_realism"):
            overrides["detail_transfer"] = st.slider("Skin detail transfer", 0.0, 1.0, 0.4, 0.05)
            overrides["grain_match"] = st.slider("Grain match", 0.0, 1.0, 1.0, 0.05)
            overrides["relight"] = st.slider("Relight strength", 0.0, 1.0, 1.0, 0.05)
            overrides["preserve_mouth_interior"] = st.checkbox("Keep the target's real teeth", value=True)
            overrides["focus_match"] = st.checkbox("Focus match", value=True)

    return dict(quality_profile=profile, restorer=restorer, restorer_weight=weight,
                use_parser=use_parser, use_occluder=use_occluder, dfm_path=dfm_path,
                swapper=swapper, identity_boost=boost, realism_preset=preset, realism_overrides=overrides)


def gallery_faceset(name, records):
    """Reuse the selected person's stored embeddings without rescanning crops."""
    import numpy as np
    from reface import FaceData, Faceset

    faceset = Faceset(name)
    for record in records:
        try:
            embedding = np.asarray(record.get("embedding"), np.float32)
            if embedding.shape != (512,) or not np.isfinite(embedding).all() or np.linalg.norm(embedding) < 1e-8:
                continue
            faceset.add_face(FaceData(
                image_path=record.get("image_path") or record.get("source_path") or "",
                embedding=embedding, pose=tuple(record.get("pose") or (0.0, 0.0, 0.0)),
                bbox=[0, 0, 0, 0], quality=float(record.get("quality_score") or 0.0),
            ))
        except (TypeError, ValueError):
            continue
    return faceset


def target_files(data_sources):
    """List the same configured folders accepted by the former gallery workflow."""
    extensions = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".mp4", ".avi", ".mkv", ".mov", ".wmv", ".webm"}
    paths = set()
    for source in data_sources:
        folder = Path(source["path"])
        if not folder.is_dir():
            continue
        candidates = folder.rglob("*") if source.get("include_subfolders", True) else folder.iterdir()
        paths.update(str(path) for path in candidates if path.is_file() and path.suffix.lower() in extensions)
    return sorted(paths)


def select_target(state, path, signature=None):
    """Discard reference faces when the target changes, including same-name uploads."""
    path = str(path)
    if state.get("v2_target_path") != path or state.get("reface_target_signature") != signature:
        for key in list(state):
            if str(key).startswith("v2_target_face_"):
                del state[key]
        state["v2_detected_faces"] = []
        state["v2_selected_target_faces"] = []
    state["v2_target_path"] = path
    state["reface_target_signature"] = signature
    state["v2_is_video"] = Path(path).suffix.lower() in {".mp4", ".avi", ".mkv", ".mov", ".wmv", ".webm"}


def stage_target_upload(state, uploaded_file, directory):
    """Do not rewrite a large video on every quality/face-selection rerun."""
    import hashlib
    upload_id = getattr(uploaded_file, "file_id", None)
    signature = str(upload_id) if upload_id is not None else hashlib.sha256(uploaded_file.getbuffer()).hexdigest()
    signature = "upload:" + signature
    directory = Path(directory)
    path = directory / Path(uploaded_file.name).name
    if state.get("reface_target_signature") != signature or not path.is_file():
        directory.mkdir(parents=True, exist_ok=True)
        path.write_bytes(uploaded_file.getbuffer())
    select_target(state, path, signature)
    return path


def selected_targets(state):
    """New jobs select identities explicitly; never fall back to detection order."""
    import numpy as np
    if state.get("reface_replace_all", True):
        return None, None
    indices = list(state.get("v2_selected_target_faces", []))
    refs = [face.get("embedding") for face in state.get("v2_detected_faces", [])]
    if not indices:
        raise ValueError("Select a target face or enable Replace all faces.")
    if any(not isinstance(index, int) or index < 0 or index >= len(refs) for index in indices):
        raise ValueError("Detect faces again to select people in this target.")
    try:
        vectors = np.asarray(refs, dtype=np.float32)
        valid = vectors.shape == (len(refs), 512) and np.isfinite(vectors).all() and (np.linalg.norm(vectors, axis=1) > 1e-8).all()
    except (TypeError, ValueError):
        valid = False
    if not valid:
        raise ValueError("Detect faces again to track the selected people throughout the video.")
    return indices, refs
