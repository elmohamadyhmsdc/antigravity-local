"""
Unit tests for URL routing in Antigravity Local dashboard.
Run with: python test_routing.py
"""
import sys
from pathlib import Path

# Add current directory to path
sys.path.insert(0, str(Path(__file__).parent))

from nav_routes import (
    NAV_PAGES,
    PAGE_TO_PRIMARY_SLUG,
    ROUTE_MAP,
    resolve_route,
    get_primary_slug,
    resolve_gallery_view,
)

def test_all_pages_have_primary_slugs():
    assert len(NAV_PAGES) == 9, f"Expected 9 pages, got {len(NAV_PAGES)}"
    for page in NAV_PAGES:
        assert page in PAGE_TO_PRIMARY_SLUG, f"Missing primary slug for {page}"
        slug = PAGE_TO_PRIMARY_SLUG[page]
        assert isinstance(slug, str) and len(slug) > 0
        # Bidirectional test
        resolved = resolve_route(slug)
        assert resolved == page, f"Primary slug '{slug}' resolved to '{resolved}' instead of '{page}'"
    print("PASS: test_all_pages_have_primary_slugs")

def test_numeric_indices():
    for idx, page in enumerate(NAV_PAGES, start=1):
        assert resolve_route(idx) == page, f"Numeric int {idx} failed to resolve to {page}"
        assert resolve_route(str(idx)) == page, f"Numeric str '{idx}' failed to resolve to {page}"
    # Out of bounds
    assert resolve_route("0") is None
    assert resolve_route("10") is None
    print("PASS: test_numeric_indices")

def test_slug_aliases():
    cases = {
        "home": "📊 Dashboard",
        "dash": "📊 Dashboard",
        "data_sources": "📁 Data Sources",
        "data-sources": "📁 Data Sources",
        "sources": "📁 Data Sources",
        "gallery": "👥 Gallery",
        "photos": "👥 Gallery",
        "reface": "🎭 Reface",
        "swap": "🎭 Reface",
        "reface_v2": "🎭 Reface V2",
        "reface-v2": "🎭 Reface V2",
        "v2": "🎭 Reface V2",
        "undress": "✨ Magic Undress",
        "magic_undress": "✨ Magic Undress",
        "restyle": "✨ Magic Undress",
        "merge": "🔀 Merge People",
        "merge_people": "🔀 Merge People",
        "lora": "🧬 Character LoRA",
        "character_lora": "🧬 Character LoRA",
        "settings": "⚙️ Settings",
        "config": "⚙️ Settings",
    }
    for slug, expected in cases.items():
        res = resolve_route(slug)
        assert res == expected, f"Slug '{slug}' resolved to '{res}', expected '{expected}'"
        # Test case insensitivity
        res_upper = resolve_route(slug.upper())
        assert res_upper == expected, f"Upper slug '{slug.upper()}' failed to resolve"
    print("PASS: test_slug_aliases")

def test_arabic_aliases():
    arabic_cases = {
        "لوحة_التحكم": "📊 Dashboard",
        "الرئيسية": "📊 Dashboard",
        "المصادر": "📁 Data Sources",
        "مصادر_البيانات": "📁 Data Sources",
        "المعرض": "👥 Gallery",
        "تبديل_الوجه": "🎭 Reface",
        "ريفيس": "🎭 Reface",
        "ريفيس_v2": "🎭 Reface V2",
        "الملابس": "✨ Magic Undress",
        "تغيير_الملابس": "✨ Magic Undress",
        "دمج": "🔀 Merge People",
        "دمج_الأشخاص": "🔀 Merge People",
        "لورا": "🧬 Character LoRA",
        "الإعدادات": "⚙️ Settings",
        "الاعدادات": "⚙️ Settings",
    }
    for alias, expected in arabic_cases.items():
        res = resolve_route(alias)
        assert res == expected, f"Arabic alias '{alias}' resolved to '{res}', expected '{expected}'"
    print("PASS: test_arabic_aliases")

def test_gallery_subviews():
    assert resolve_gallery_view("all") == "📷 All Media"
    assert resolve_gallery_view("media") == "📷 All Media"
    assert resolve_gallery_view("person") == "By Person"
    assert resolve_gallery_view("unassigned") == "Unassigned Faces"
    assert resolve_gallery_view("invalid_mode") is None
    print("PASS: test_gallery_subviews")

def test_invalid_and_empty():
    assert resolve_route(None) is None
    assert resolve_route("") is None
    assert resolve_route("   ") is None
    assert resolve_route("non_existent_page_xyz") is None
    print("PASS: test_invalid_and_empty")

if __name__ == "__main__":
    print("Running URL Routing Unit Tests...")
    test_all_pages_have_primary_slugs()
    test_numeric_indices()
    test_slug_aliases()
    test_arabic_aliases()
    test_gallery_subviews()
    test_invalid_and_empty()
    print("\n🎉 ALL ROUTING TESTS PASSED SUCCESSFULLY!")
