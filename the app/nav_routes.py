"""
URL Routing and Deep Linking helpers for Antigravity Local Dashboard.
Provides two-way synchronization between URL query parameters and menu navigation tabs.
"""
from typing import Optional, Dict, List, Any

# All navigation pages in display order
NAV_PAGES: List[str] = [
    "📊 Dashboard",
    "📁 Data Sources",
    "👥 Gallery",
    "🎭 Reface",
    "🎭 Reface V2",
    "✨ Magic Undress",
    "🔀 Merge People",
    "🧬 Character LoRA",
    "⚙️ Settings",
]

# Primary clean URL slug for each page
PAGE_TO_PRIMARY_SLUG: Dict[str, str] = {
    "📊 Dashboard": "dashboard",
    "📁 Data Sources": "sources",
    "👥 Gallery": "gallery",
    "🎭 Reface": "reface",
    "🎭 Reface V2": "reface_v2",
    "✨ Magic Undress": "undress",
    "🔀 Merge People": "merge",
    "🧬 Character LoRA": "lora",
    "⚙️ Settings": "settings",
}

# Mapping of all slugs, aliases, numbers, and Arabic names to canonical page names
ROUTE_MAP: Dict[str, str] = {
    # 1. Dashboard
    "dashboard": "📊 Dashboard",
    "home": "📊 Dashboard",
    "dash": "📊 Dashboard",
    "1": "📊 Dashboard",
    "لوحة_التحكم": "📊 Dashboard",
    "لوحة-التحكم": "📊 Dashboard",
    "الرئيسية": "📊 Dashboard",

    # 2. Data Sources
    "sources": "📁 Data Sources",
    "data_sources": "📁 Data Sources",
    "data-sources": "📁 Data Sources",
    "datasources": "📁 Data Sources",
    "data": "📁 Data Sources",
    "2": "📁 Data Sources",
    "المصادر": "📁 Data Sources",
    "مصادر_البيانات": "📁 Data Sources",
    "مصادر-البيانات": "📁 Data Sources",

    # 3. Gallery
    "gallery": "👥 Gallery",
    "photos": "👥 Gallery",
    "media": "👥 Gallery",
    "3": "👥 Gallery",
    "المعرض": "👥 Gallery",
    "الصور": "👥 Gallery",

    # 4. Reface
    "reface": "🎭 Reface",
    "swap": "🎭 Reface",
    "faceswap": "🎭 Reface",
    "4": "🎭 Reface",
    "تبديل_الوجه": "🎭 Reface",
    "تبديل-الوجه": "🎭 Reface",
    "ريفيس": "🎭 Reface",

    # 5. Reface V2
    "reface_v2": "🎭 Reface V2",
    "reface-v2": "🎭 Reface V2",
    "refacev2": "🎭 Reface V2",
    "v2": "🎭 Reface V2",
    "v3": "🎭 Reface V2",
    "5": "🎭 Reface V2",
    "ريفيس_v2": "🎭 Reface V2",
    "ريفيس-v2": "🎭 Reface V2",

    # 6. Magic Undress
    "undress": "✨ Magic Undress",
    "magic_undress": "✨ Magic Undress",
    "magic-undress": "✨ Magic Undress",
    "magicundress": "✨ Magic Undress",
    "restyle": "✨ Magic Undress",
    "6": "✨ Magic Undress",
    "الملابس": "✨ Magic Undress",
    "تغيير_الملابس": "✨ Magic Undress",
    "تغيير-الملابس": "✨ Magic Undress",

    # 7. Merge People
    "merge": "🔀 Merge People",
    "merge_people": "🔀 Merge People",
    "merge-people": "🔀 Merge People",
    "mergepeople": "🔀 Merge People",
    "7": "🔀 Merge People",
    "دمج": "🔀 Merge People",
    "دمج_الأشخاص": "🔀 Merge People",
    "دمج_الاشخاص": "🔀 Merge People",
    "دمج-الاشخاص": "🔀 Merge People",

    # 8. Character LoRA
    "lora": "🧬 Character LoRA",
    "character_lora": "🧬 Character LoRA",
    "character-lora": "🧬 Character LoRA",
    "characterlora": "🧬 Character LoRA",
    "train": "🧬 Character LoRA",
    "8": "🧬 Character LoRA",
    "لورا": "🧬 Character LoRA",

    # 9. Settings
    "settings": "⚙️ Settings",
    "config": "⚙️ Settings",
    "setup": "⚙️ Settings",
    "9": "⚙️ Settings",
    "الاعدادات": "⚙️ Settings",
    "الإعدادات": "⚙️ Settings",
}

# Auto-register full titles and stripped title variations
for _title in NAV_PAGES:
    ROUTE_MAP[_title.lower()] = _title
    # Strip emojis and leading symbols if any
    _parts = _title.split(maxsplit=1)
    if len(_parts) > 1:
        _clean_text = _parts[1].strip().lower()
        ROUTE_MAP[_clean_text] = _title
        ROUTE_MAP[_clean_text.replace(" ", "_")] = _title
        ROUTE_MAP[_clean_text.replace(" ", "-")] = _title


def resolve_route(route_input: Optional[Any]) -> Optional[str]:
    """
    Given a route string, slug, alias, number, or title, returns the matching NAV_PAGE title.
    Returns None if no match found.
    """
    if route_input is None:
        return None
    
    val = str(route_input).strip().lower()
    if not val:
        return None
    
    # 1. Direct lookup in map
    if val in ROUTE_MAP:
        return ROUTE_MAP[val]
    
    # 2. Check 1-based numeric index
    try:
        idx = int(val)
        if 1 <= idx <= len(NAV_PAGES):
            return NAV_PAGES[idx - 1]
    except ValueError:
        pass
    
    return None


def get_primary_slug(page_title: str) -> str:
    """Returns the primary URL slug for a canonical page title."""
    return PAGE_TO_PRIMARY_SLUG.get(page_title, "dashboard")


def get_url_route(st_module: Any) -> Optional[str]:
    """
    Extract route slug from Streamlit query params.
    Checks 'page', 'tab', and 'route' keys.
    Compatible with both modern st.query_params and legacy st.experimental_get_query_params.
    """
    try:
        if hasattr(st_module, "query_params"):
            qp = st_module.query_params
            val = qp.get("page") or qp.get("tab") or qp.get("route")
            if val is not None:
                # In modern Streamlit, qp.get returns string or list of strings
                if isinstance(val, list) and val:
                    return str(val[0])
                return str(val)
        elif hasattr(st_module, "experimental_get_query_params"):
            qp = st_module.experimental_get_query_params()
            for key in ("page", "tab", "route"):
                if key in qp and qp[key]:
                    return str(qp[key][0])
    except Exception:
        pass
    return None


def set_url_route(st_module: Any, slug: str):
    """
    Update the URL query parameter in Streamlit.
    """
    try:
        if hasattr(st_module, "query_params"):
            st_module.query_params["page"] = slug
        elif hasattr(st_module, "experimental_set_query_params"):
            st_module.experimental_set_query_params(page=slug)
    except Exception:
        pass


# Gallery view mode aliases
GALLERY_VIEW_MAP: Dict[str, str] = {
    "all": "📷 All Media",
    "media": "📷 All Media",
    "photos": "📷 All Media",
    "all_media": "📷 All Media",
    "archive": "📷 All Media",
    "person": "By Person",
    "people": "By Person",
    "by_person": "By Person",
    "characters": "By Person",
    "identities": "By Person",
    "unassigned": "Unassigned Faces",
    "unassigned_faces": "Unassigned Faces",
    "triage": "Unassigned Faces",
    "inbox": "Unassigned Faces",
    "insights": "📊 Biometric Insights",
    "analytics": "📊 Biometric Insights",
    "quality": "📊 Biometric Insights",
    "stats": "📊 Biometric Insights",
}

def resolve_gallery_view(view_input: Optional[Any]) -> Optional[str]:
    """Resolve sub-view query parameter for Gallery."""
    if not view_input:
        return None
    val = str(view_input).strip().lower()
    return GALLERY_VIEW_MAP.get(val)


def get_gallery_person_param(st_module: Any) -> Optional[int]:
    """Extract person_id integer from Streamlit query params if present."""
    try:
        val = None
        if hasattr(st_module, "query_params"):
            val = st_module.query_params.get("person_id") or st_module.query_params.get("person")
        elif hasattr(st_module, "experimental_get_query_params"):
            qp = st_module.experimental_get_query_params()
            val = (qp.get("person_id") or qp.get("person") or [None])[0]
        if val is not None:
            if isinstance(val, list) and val:
                val = val[0]
            return int(str(val).strip())
    except Exception:
        pass
    return None
