"""
Antigravity Mobile - App Icon Generator
Generates Android Adaptive Icons & Legacy Launcher Icons from an isolated master graphic.
Removes black background into a true alpha transparency layer (screen un-premultiply),
centers the icon inside the Android safe zone, and exports all density buckets.
"""

import os
import sys
import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
    import numpy as np
except ImportError:
    print("Error: Pillow and numpy are required. Run with the project's venv:")
    print(r"  ..\the app\venv\Scripts\python tools/generate_app_icons.py")
    sys.exit(1)

# Default paths
SCRIPT_DIR = Path(__file__).resolve().parent
MOBILE_DIR = SCRIPT_DIR.parent
RES_DIR = MOBILE_DIR / "android" / "app" / "src" / "main" / "res"
ASSETS_ICON_DIR = MOBILE_DIR / "assets" / "icon"

# Primary source candidates (brain artifact or local tool copy)
SOURCE_CANDIDATES = [
    Path(r"C:\Users\elmohamady\.gemini\antigravity-ide\brain\4f3521fd-e6e0-4319-87d8-4a83e4dfe055\icon_face_mesh_isolated_1791981611635.jpg"),
    SCRIPT_DIR / "icon_source.jpg",
    ASSETS_ICON_DIR / "icon_source.jpg",
]

# Android Adaptive Icon sizes (108dp x 108dp canvas)
# Safe zone: centered circular region of diameter 66dp (~61% of canvas)
ADAPTIVE_FOREGROUND_SIZES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

# Legacy Launcher Icon sizes (standard 48dp x 48dp)
LEGACY_ICON_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Default background color: Deep Dark Violet / Obsidian matching #6C5CE7 brand seed
BG_COLOR_HEX = "#120E24"
BG_COLOR_RGB = (18, 14, 36)


def extract_alpha_from_black(img: Image.Image) -> Image.Image:
    """
    Converts glowing neon on black to an RGBA image with true transparency.
    Uses luminance-based alpha and un-premultiplies RGB to maintain vivid neon colors
    without black halos when composited on any background.
    """
    img = img.convert("RGB")
    arr = np.array(img, dtype=np.float32)

    # Maximum RGB channel represents light intensity
    intensity = np.max(arr, axis=2)

    # Cut off background dark noise
    low_cut = 12.0
    ramp_end = 55.0

    alpha = np.zeros_like(intensity)
    mid_mask = (intensity >= low_cut) & (intensity < ramp_end)
    alpha[mid_mask] = (intensity[mid_mask] - low_cut) / (ramp_end - low_cut) * (ramp_end / 255.0)
    high_mask = intensity >= ramp_end
    # Soft boost on bright core lines
    alpha[high_mask] = np.clip((intensity[high_mask] / 255.0) ** 0.85 * 1.15, 0.0, 1.0)

    # Un-premultiply RGB so translucent edges don't darken
    rgb = np.zeros_like(arr)
    denom = np.maximum(alpha, 0.25)[:, :, np.newaxis]
    rgb = np.clip(arr / denom, 0.0, 255.0)

    rgba = np.dstack([rgb.astype(np.uint8), (alpha * 255.0).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def find_source_image() -> Path:
    for path in SOURCE_CANDIDATES:
        if path.exists():
            return path
    raise FileNotFoundError(
        f"Source icon image not found in candidates: {[str(p) for p in SOURCE_CANDIDATES]}"
    )


def create_solid_background(size: int, color_rgb: tuple) -> Image.Image:
    """Creates a clean background with a very subtle radial vignette/glow."""
    bg = Image.new("RGBA", (size, size), color_rgb + (255,))
    draw = ImageDraw.Draw(bg)
    # Subtle central accent glow
    center = size / 2.0
    radius = size * 0.45
    accent = (108, 92, 231)  # #6C5CE7
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        [center - radius, center - radius, center + radius, center + radius],
        fill=(accent[0], accent[1], accent[2], 35),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.18))
    bg = Image.alpha_composite(bg, glow)
    return bg


def generate_adaptive_foreground(transparent_icon: Image.Image, canvas_size: int) -> Image.Image:
    """
    Android Adaptive icon canvas is 108dp x 108dp.
    The safe zone is an inner circle of diameter 66dp (~61% of canvas).
    We scale the icon to fill ~62% of the canvas so it's large, clear,
    and guaranteed never to be clipped by any OEM squircle/circle mask.
    """
    target_dim = int(canvas_size * 0.62)
    # Fit preserving aspect ratio
    icon_w, icon_h = transparent_icon.size
    scale = target_dim / max(icon_w, icon_h)
    new_w = int(icon_w * scale)
    new_h = int(icon_h * scale)
    scaled_icon = transparent_icon.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    offset_x = (canvas_size - new_w) // 2
    offset_y = (canvas_size - new_h) // 2
    canvas.paste(scaled_icon, (offset_x, offset_y), scaled_icon)
    return canvas


def generate_legacy_icon(transparent_icon: Image.Image, size: int, round_icon: bool = False) -> Image.Image:
    """
    Generates legacy square/squircle or round ic_launcher.png.
    """
    bg = create_solid_background(size, BG_COLOR_RGB)
    
    # Scale icon to fit inside
    target_dim = int(size * 0.72)
    icon_w, icon_h = transparent_icon.size
    scale = target_dim / max(icon_w, icon_h)
    new_w = int(icon_w * scale)
    new_h = int(icon_h * scale)
    scaled_icon = transparent_icon.resize((new_w, new_h), Image.Resampling.LANCZOS)

    offset_x = (size - new_w) // 2
    offset_y = (size - new_h) // 2
    bg.paste(scaled_icon, (offset_x, offset_y), scaled_icon)

    if round_icon:
        # Circular mask with smooth anti-aliasing
        mask_scale = 4
        big_mask = Image.new("L", (size * mask_scale, size * mask_scale), 0)
        draw = ImageDraw.Draw(big_mask)
        draw.ellipse([0, 0, size * mask_scale - 1, size * mask_scale - 1], fill=255)
        mask = big_mask.resize((size, size), Image.Resampling.LANCZOS)
        
        output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        output.paste(bg, (0, 0), mask)
        return output

    return bg


def write_android_xml_resources():
    """Writes values/colors.xml and mipmap-anydpi-v26 XMLs."""
    values_dir = RES_DIR / "values"
    values_dir.mkdir(parents=True, exist_ok=True)
    colors_xml = values_dir / "colors.xml"
    colors_xml_content = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{BG_COLOR_HEX}</color>
</resources>
"""
    colors_xml.write_text(colors_xml_content, encoding="utf-8")
    print(f"  [OK] Created {colors_xml.relative_to(MOBILE_DIR)}")

    anydpi_dir = RES_DIR / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)

    adaptive_xml_content = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""
    (anydpi_dir / "ic_launcher.xml").write_text(adaptive_xml_content, encoding="utf-8")
    (anydpi_dir / "ic_launcher_round.xml").write_text(adaptive_xml_content, encoding="utf-8")
    print(f"  [OK] Created {anydpi_dir.relative_to(MOBILE_DIR)}/ic_launcher.xml & ic_launcher_round.xml")


def main():
    print("=" * 60)
    print("Antigravity Mobile - App Icon Generator")
    print("=" * 60)

    src_path = find_source_image()
    print(f"Source image: {src_path}")
    raw_img = Image.open(src_path)

    # 1. Save local copy in mobile/assets/icon/ for self-contained repo
    ASSETS_ICON_DIR.mkdir(parents=True, exist_ok=True)
    local_source = ASSETS_ICON_DIR / "icon_source.jpg"
    if not local_source.exists():
        raw_img.save(local_source, quality=95)
        print(f"Saved local archive: {local_source.relative_to(MOBILE_DIR)}")

    # 2. Extract transparency from black
    print("Extracting alpha transparency from black background...")
    transparent_icon = extract_alpha_from_black(raw_img)
    
    # Auto-crop tight bounding box
    bbox = transparent_icon.getbbox()
    if bbox:
        transparent_icon = transparent_icon.crop(bbox)
        # Pad to square
        w, h = transparent_icon.size
        side = max(w, h)
        square_icon = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square_icon.paste(transparent_icon, ((side - w) // 2, (side - h) // 2))
        transparent_icon = square_icon

    master_path = ASSETS_ICON_DIR / "antigravity_icon_transparent.png"
    transparent_icon.resize((1024, 1024), Image.Resampling.LANCZOS).save(master_path, "PNG")
    print(f"  [OK] Saved Master Transparent Icon: {master_path.relative_to(MOBILE_DIR)} (1024x1024)")

    # 3. Write XML definitions
    print("Configuring Android XML resources...")
    write_android_xml_resources()

    # 4. Generate Adaptive Foreground icons
    print("Generating Android Adaptive Foreground icons (ic_launcher_foreground.png)...")
    for bucket, size in ADAPTIVE_FOREGROUND_SIZES.items():
        bucket_dir = RES_DIR / bucket
        bucket_dir.mkdir(parents=True, exist_ok=True)
        fg = generate_adaptive_foreground(transparent_icon, size)
        fg_path = bucket_dir / "ic_launcher_foreground.png"
        fg.save(fg_path, "PNG")
        print(f"  [OK] {bucket}/ic_launcher_foreground.png ({size}x{size})")

    # 5. Generate Legacy icons (ic_launcher.png & ic_launcher_round.png)
    print("Generating Legacy & Round Icons...")
    for bucket, size in LEGACY_ICON_SIZES.items():
        bucket_dir = RES_DIR / bucket
        bucket_dir.mkdir(parents=True, exist_ok=True)
        
        legacy_std = generate_legacy_icon(transparent_icon, size, round_icon=False)
        legacy_std_path = bucket_dir / "ic_launcher.png"
        legacy_std.save(legacy_std_path, "PNG")

        legacy_round = generate_legacy_icon(transparent_icon, size, round_icon=True)
        legacy_round_path = bucket_dir / "ic_launcher_round.png"
        legacy_round.save(legacy_round_path, "PNG")
        print(f"  [OK] {bucket}/ic_launcher.png & ic_launcher_round.png ({size}x{size})")

    # 6. Generate Preview Sheet
    preview_size = 384
    preview_fg = generate_adaptive_foreground(transparent_icon, preview_size)
    preview_bg = create_solid_background(preview_size, BG_COLOR_RGB)
    preview_composite = Image.alpha_composite(preview_bg, preview_fg)
    preview_round = generate_legacy_icon(transparent_icon, preview_size, round_icon=True)

    preview_sheet = Image.new("RGBA", (preview_size * 2 + 40, preview_size + 40), (20, 20, 24, 255))
    preview_sheet.paste(preview_composite, (20, 20), preview_composite)
    preview_sheet.paste(preview_round, (preview_size + 20, 20), preview_round)
    preview_path = ASSETS_ICON_DIR / "preview_launcher.png"
    preview_sheet.save(preview_path, "PNG")
    print(f"  [OK] Preview sheet saved: {preview_path.relative_to(MOBILE_DIR)}")

    print("=" * 60)
    print("Successfully generated all Antigravity Android launcher icons!")
    print(f"Background color: {BG_COLOR_HEX} (editable in {RES_DIR / 'values' / 'colors.xml'})")
    print("=" * 60)


if __name__ == "__main__":
    main()
