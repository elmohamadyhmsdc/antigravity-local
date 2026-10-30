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


def profile_catalog(available):
    return {name: profile_defaults(name, available) for name in QUALITY_PROFILES}
