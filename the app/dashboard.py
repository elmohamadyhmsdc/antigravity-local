"""
Your Gallery - Streamlit Dashboard
Interactive gallery for face management and LoRA export
"""

import os
import sys
from pathlib import Path
from typing import List, Optional, Dict, Any
import io
import zipfile
import shutil
import uuid
from datetime import datetime

import streamlit as st
import numpy as np
from PIL import Image
from dotenv import load_dotenv
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import time
import json
import subprocess

class ETACalculator:
    """Helper to calculate and format estimated time remaining"""
    def __init__(self, total_items: int):
        self.total_items = total_items
        self.start_time = time.time()
        self.last_update_time = self.start_time
        
    def get_eta_string(self, current_item: int) -> str:
        if current_item <= 0:
            return "Estimating..."
            
        elapsed = time.time() - self.start_time
        avg_time_per_item = elapsed / current_item
        remaining_items = self.total_items - current_item
        remaining_time = avg_time_per_item * remaining_items
        
        if remaining_time < 0:
            remaining_time = 0
            
        # Format duration
        if remaining_time > 3600:
            h = int(remaining_time // 3600)
            m = int((remaining_time % 3600) // 60)
            s = int(remaining_time % 60)
            return f"{h}h {m}m {s}s"
        elif remaining_time > 60:
            m = int(remaining_time // 60)
            s = int(remaining_time % 60)
            return f"{m}m {s}s"
        else:
            return f"{int(remaining_time)}s"

# Import database functions from the new JsonDatabase module
from database import (
    init_db,
    get_stats,
    get_all_persons,
    get_faces_by_person,
    get_all_faces,
    add_person,
    merge_persons,
    assign_face_to_person,
    find_similar_faces,
    delete_face,
    set_person_avatar,
    get_person_avatar_face,
    batch_assign_faces,
    JsonDatabase
)
from job_manager import JobManager, JobStatus, add_job_to_queue
from undress_core import (
    DEFAULT_NEGATIVE_PROMPT,
    DEFAULT_PROMPT,
    INPUT_DIR,
    SETUP_INSTRUCTIONS,
    VENV_AI_PYTHON,
    annotate_face_preview,
)
from nav_routes import (
    NAV_PAGES,
    PAGE_TO_PRIMARY_SLUG,
    resolve_route,
    get_primary_slug,
    get_url_route,
    set_url_route,
    resolve_gallery_view,
    get_gallery_person_param,
)

# Load environment variables
load_dotenv()

# Add parent directory to path for imports (this script re-runs on every
# Streamlit rerun, so only insert it once)
if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))

# Add ALL NVIDIA DLL paths for ONNX Runtime CUDA support. Must be idempotent:
# see cuda_dll_dirs.py for the WinError 206 that re-registering on each rerun caused.
from cuda_dll_dirs import add_nvidia_dll_dirs
add_nvidia_dll_dirs()

# Initialize the JsonDatabase
db = JsonDatabase()
DB_AVAILABLE = True # JsonDatabase is always available if imported successfully

# from mask_utils import generate_body_mask (Removed)

@st.cache_resource
def get_face_analyzer():
    from insightface.app import FaceAnalysis
    app = FaceAnalysis(name='buffalo_l')
    # Use CUDA if available, else CPU (ctx_id=0 for GPU 0, -1 for CPU)
    # The user has GPU (implied by previous context/requirements).
    app.prepare(ctx_id=0, det_size=(640, 640))
    return app


_IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}

UNDRESS_HELP = {
    "source": (
        "Where the photo comes from. Upload a still image, or pick a person from the "
        "gallery whose source file is a photo (video frames cannot be used here)."
    ),
    "upload": (
        "PNG / JPG / WebP still. Only detected clothes are inpainted. Hair, face, hands, "
        "arms, exposed skin, and the background stay from the original photo."
    ),
    "prompt": (
        "What you want the model to draw in the clothes region. Be specific: garment "
        "type, color, fabric, lighting. Only the garment pixels are rewritten. Hair, face, "
        "hands, and already-exposed skin stay from the source."
    ),
    "neg": (
        "What to avoid in the generated region (blur, extra limbs, cartoon look, text). "
        "The model steers away from these terms during denoising."
    ),
    "seed": (
        "Random number that locks the noise pattern. -1 = a new random result every job. "
        "Any other integer (e.g. 42) repeats the same generation if prompt, steps, strength, "
        "and image are unchanged — useful to A/B a slider without the look jumping randomly."
    ),
    "steps": (
        "How many denoising passes the model runs (15–50). More steps = more time and usually "
        "cleaner fabric/detail; past ~30 the gain is small. 20 is faster for tests; 30–40 is "
        "the quality default. This is not the same as strength."
    ),
    "strength": (
        "How hard the masked clothes are rewritten, 0.3–1.0. Below 1.0 the garment area "
        "starts from a base repainted in the prompt’s colour that keeps the original folds "
        "and neckline, so the model refines fabric already in the right place. Around 0.6 is "
        "the sweet spot. At 1.0 it starts from pure noise instead — more freedom, but with "
        "skin all around it often paints skin where the garment should be. Unmasked pixels "
        "stay from the source regardless."
    ),
    "guidance": (
        "How literally the model follows the prompt, 3–12. Around 6 gives natural fabric; "
        "above ~8 realisticVision turns waxy and plastic-looking. Raise it only if the "
        "garment ignores the prompt."
    ),
    "refs": (
        "Optional photos of the garment or style you want. They steer the generated clothes "
        "via IP-Adapter, so you get that specific dress instead of a generic one. Several "
        "images are combined. Leave empty to rely on the prompt alone."
    ),
    "ref_scale": (
        "How strongly the reference images pull the result, 0–1. Around 0.6 balances the "
        "reference against the prompt; near 1.0 the references dominate and can fight the "
        "pose; 0 disables them."
    ),
    "refine": (
        "Second pass that re-denoises the finished garment at the photo’s native resolution "
        "in overlapping tiles. This is what brings back fabric weave and shadow detail that "
        "the 768px first pass cannot hold. Costs roughly a minute per few tiles."
    ),
    "refine_strength": (
        "How much the refine pass may change the garment, 0.1–0.6. Around 0.28 adds texture "
        "while keeping the shape from the first pass. Above ~0.45 it starts redesigning the "
        "garment and can undo the fit."
    ),
}


def detect_undress_subject(image_rgb: Image.Image):
    """Largest face bbox (xyxy ints), or None if no face."""
    app = get_face_analyzer()
    img_cv = np.array(image_rgb)[:, :, ::-1]
    faces = app.get(img_cv)
    if not faces:
        return None
    main_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
    return [int(v) for v in main_face.bbox]

# Page configuration
st.set_page_config(
    page_title="Your Gallery",
    page_icon="🔬",
    layout="wide",
    initial_sidebar_state="expanded"
)

def load_css(file_path):
    with open(file_path) as f:
        st.markdown(f'<style>{f.read()}</style>', unsafe_allow_html=True)

try:
    load_css(Path(__file__).parent / "assets" / "styles.css")
except Exception as e:
    st.warning(f"Could not load custom CSS: {e}")

# Session state for data sources
if 'data_sources' not in st.session_state:
    st.session_state.data_sources = []

# Config file for persisting data sources
CONFIG_FILE = Path(__file__).parent / "data_sources.json"


def load_data_sources():
    """Load saved data sources from config file"""
    import json
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return []


def save_data_sources(sources: List[Dict]):
    """Save data sources to config file"""
    import json
    with open(CONFIG_FILE, 'w') as f:
        json.dump(sources, f, indent=2)


def get_database_stats() -> Dict[str, int]:
    """Get database statistics using JsonDatabase"""
    stats = get_stats()
    # Add db_offline flag for compatibility with existing UI logic
    stats["db_offline"] = False
    return stats

def get_source_analytics() -> pd.DataFrame:
    """Get analytics about source files"""
    faces = get_all_faces()

    # Count faces by source_path
    source_counts = {}
    for face in faces:
        source = face.get("source_path", "Unknown")
        # Just use the filename or immediate parent folder for cleaner display
        try:
            # If it's a file path, get the parent folder name
            if os.path.isfile(source):
                source = str(Path(source).parent.name)
            else:
                source = str(Path(source).name)
        except:
            pass

        source_counts[source] = source_counts.get(source, 0) + 1

    data = [
        {"source": source, "face_count": count}
        for source, count in source_counts.items()
    ]

    # Sort by count desc
    data.sort(key=lambda x: x["face_count"], reverse=True)
    return pd.DataFrame(data)

def get_all_persons() -> List[Dict[str, Any]]:
    """Get all persons with their face counts"""
    persons = db.get_all_persons() # This calls the function from database.py
    result = []
    for p in persons:
        face_count = len(get_faces_by_person(p["id"]))
        result.append({
            "id": p["id"],
            "name": p.get("name") or f"Person #{p['id']}",
            "face_count": face_count,
            "created_at": p.get("created_at")
        })
    return result


def get_faces_for_person(person_id: int, limit: int = 50) -> List[Dict[str, Any]]:
    """Get faces for a specific person"""
    all_faces = get_faces_by_person(person_id)
    # Sort by quality score descending
    all_faces.sort(key=lambda x: x.get("quality_score", 0), reverse=True)
    return all_faces[:limit]


def delete_person(person_id: int, delete_faces: bool = False):
    """Delete a person. If delete_faces is True, delete face images from disk too; otherwise unassign them."""
    if delete_faces:
        p_faces = get_faces_by_person(person_id)
        for f in p_faces:
            delete_face(f["id"], delete_file=True)
    db.delete_person(person_id)


def count_media_files(folder_path: str) -> Dict[str, int]:
    """Count images and videos in a folder"""
    folder = Path(folder_path)
    if not folder.exists():
        return {"images": 0, "videos": 0, "total": 0}

    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp', '.gif'}
    video_extensions = {'.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm'}

    images = 0
    videos = 0

    for f in folder.rglob('*'):
        if f.is_file():
            ext = f.suffix.lower()
            if ext in image_extensions:
                images += 1
            elif ext in video_extensions:
                videos += 1

    return {"images": images, "videos": videos, "total": images + videos}


# Load saved data sources on startup
if 'sources_loaded' not in st.session_state:
    st.session_state.data_sources = load_data_sources()
    st.session_state.sources_loaded = True


# --- URL Routing Sync ---
url_route = get_url_route(st)
resolved_page_from_url = resolve_route(url_route)

# Check if there is a pending navigation request from a button click on previous run
if "_pending_nav_page" in st.session_state and st.session_state._pending_nav_page:
    pending = st.session_state.pop("_pending_nav_page")
    resolved_pending = resolve_route(pending)
    if resolved_pending:
        st.session_state.active_nav_page = resolved_pending
        st.session_state._last_url_slug = get_primary_slug(resolved_pending)
        set_url_route(st, st.session_state._last_url_slug)

# Initialize or synchronize session state with URL route
if 'active_nav_page' not in st.session_state:
    if resolved_page_from_url:
        st.session_state.active_nav_page = resolved_page_from_url
        st.session_state._last_url_slug = get_primary_slug(resolved_page_from_url)
    else:
        st.session_state.active_nav_page = NAV_PAGES[0]
        st.session_state._last_url_slug = get_primary_slug(NAV_PAGES[0])
    set_url_route(st, st.session_state._last_url_slug)
else:
    # URL changed externally (e.g., browser Back/Forward or manual URL change)
    if url_route and url_route.strip().lower() != st.session_state.get('_last_url_slug', '').strip().lower():
        if resolved_page_from_url and resolved_page_from_url != st.session_state.active_nav_page:
            st.session_state.active_nav_page = resolved_page_from_url
            st.session_state._last_url_slug = get_primary_slug(resolved_page_from_url)
            set_url_route(st, st.session_state._last_url_slug)

def on_nav_page_change():
    """Update URL query parameter when user selects a menu tab."""
    selected_page = st.session_state.get("active_nav_page", NAV_PAGES[0])
    slug = get_primary_slug(selected_page)
    st.session_state._last_url_slug = slug
    set_url_route(st, slug)

def navigate_to(page_or_route: str):
    """Programmatically navigate to any page and update the URL safely across widget lifecycles."""
    resolved = resolve_route(page_or_route)
    if resolved:
        slug = get_primary_slug(resolved)
        st.session_state._pending_nav_page = resolved
        st.session_state._last_url_slug = slug
        set_url_route(st, slug)
        st.rerun()

# Sidebar
with st.sidebar:
    st.markdown("""
    <div class="sidebar-brand-box">
        <div class="sidebar-brand-title">🔬 Your Gallery</div>
        <div style="display: flex; justify-content: center; gap: 8px; margin-top: 4px;">
            <span class="sidebar-status-pill">● Studio v1.2</span>
        </div>
    </div>
    """, unsafe_allow_html=True)
    st.markdown("---")
    
    # Navigation with URL routing
    page = st.radio(
        "Navigation",
        NAV_PAGES,
        key="active_nav_page",
        on_change=on_nav_page_change,
        label_visibility="collapsed"
    )
    
    st.markdown("---")
    
    # Quick stats
    with st.container(border=True):
        st.markdown("##### 📈 Quick Stats")
        stats = get_database_stats()
        if stats.get("db_offline"):
            st.warning("⚠️ Database Offline")
            st.caption("Reface still works!")
        else:
            col1, col2 = st.columns(2)
            with col1:
                st.metric("Faces", stats["total_faces"])
            with col2:
                st.metric("Persons", stats["total_persons"])
            st.metric("Unassigned", stats["unassigned_faces"])


# Mobile App Bar (displayed on small screens)
st.markdown(f"""
<div class="mobile-app-bar">
    <div class="mobile-app-brand">
        <span class="mobile-brand-icon">🔬</span>
        <span class="mobile-brand-name">Your Gallery</span>
    </div>
    <div class="mobile-page-badge">
        <span>{page}</span>
    </div>
</div>
""", unsafe_allow_html=True)

# Main content based on page selection
if page == "📱 Mobile Devices":
    from mobile_devices_page import render_mobile_devices
    render_mobile_devices()

elif page == "📊 Dashboard":
    st.title("📊 Dashboard")
    st.markdown("Overview of your biometric gallery")
    
    if stats.get("db_offline"):
        st.warning("⚠️ **Database Offline** - PostgreSQL is not running. Dashboard statistics are unavailable.")
        st.info("💡 **Tip**: The **Reface** and **Reface V2** pages still work! Use saved facesets or upload files directly.")
    else:
        col1, col2, col3, col4 = st.columns(4)
        
        with col1:
            st.markdown("""
            <div class="stats-card stats-card-violet">
                <div class="stats-card-header">
                    <div class="stats-card-icon">👤</div>
                </div>
                <div class="stats-card-value">{}</div>
                <div class="stats-card-label">Total Faces</div>
            </div>
            """.format(stats["total_faces"]), unsafe_allow_html=True)
        
        with col2:
            st.markdown("""
            <div class="stats-card stats-card-indigo">
                <div class="stats-card-header">
                    <div class="stats-card-icon">👥</div>
                </div>
                <div class="stats-card-value">{}</div>
                <div class="stats-card-label">People</div>
            </div>
            """.format(stats["total_persons"]), unsafe_allow_html=True)
        
        with col3:
            st.markdown("""
            <div class="stats-card stats-card-amber">
                <div class="stats-card-header">
                    <div class="stats-card-icon">❓</div>
                </div>
                <div class="stats-card-value">{}</div>
                <div class="stats-card-label">Unassigned Faces</div>
            </div>
            """.format(stats["unassigned_faces"]), unsafe_allow_html=True)
        
        with col4:
            avg_per_person = stats["total_faces"] / max(stats["total_persons"], 1)
            st.markdown("""
            <div class="stats-card stats-card-emerald">
                <div class="stats-card-header">
                    <div class="stats-card-icon">📈</div>
                </div>
                <div class="stats-card-value">{:.1f}</div>
                <div class="stats-card-label">Avg Faces / Person</div>
            </div>
            """.format(avg_per_person), unsafe_allow_html=True)
        
        st.markdown("---")
        
        # Recent faces
        st.subheader("🆕 Recent Faces")
        
        all_faces = get_all_faces()
        # Sort by created_at desc
        recent_faces = sorted(
            all_faces, 
            key=lambda x: x.get("created_at", ""), 
            reverse=True
        )[:12]
        
        if recent_faces:
            cols = st.columns(6)
            for i, face in enumerate(recent_faces):
                with cols[i % 6]:
                    image_path = face.get("image_path")
                    if image_path and os.path.exists(image_path):
                        st.image(image_path, caption=f"Q: {face.get('quality_score', 0):.2f}", use_container_width=True)
                    else:
                        st.write("Image not found")
        else:
            st.info("No faces in database yet. Go to 'Data Sources' to add photos/videos!")


elif page == "📁 Data Sources":
    st.title("📁 Data Sources")
    st.markdown("Add folders containing photos or videos to extract faces from")
    
    # Tab for different input methods
    tab1, tab2 = st.tabs(["📂 Add Folder Path", "📤 Upload Files"])
    
    with tab1:
        st.subheader("Add Folder Path")
        st.info("Enter a folder path containing images or videos. The app will process files in-place without moving them.")
        
        with st.form("add_folder"):
            folder_path = st.text_input(
                "Folder Path",
                placeholder="e.g., D:/Photos/MyAlbum or C:/Videos/Collection"
            )
            source_name = st.text_input(
                "Source Name (optional)",
                placeholder="e.g., 'Family Photos 2024'"
            )
            
            col1, col2 = st.columns(2)
            with col1:
                include_subfolders = st.checkbox("Include subfolders", value=True)
            with col2:
                process_videos = st.checkbox("Process videos", value=True)
            
            if st.form_submit_button("➕ Add Data Source", type="primary"):
                if folder_path:
                    folder = Path(folder_path)
                    if folder.exists():
                        # Count files
                        media_count = count_media_files(folder_path)
                        
                        # Add to sources
                        new_source = {
                            "path": folder_path,
                            "name": source_name or folder.name,
                            "include_subfolders": include_subfolders,
                            "process_videos": process_videos,
                            "added_at": datetime.now().isoformat(),
                            "processed": False,
                            "images": media_count["images"],
                            "videos": media_count["videos"]
                        }
                        st.session_state.data_sources.append(new_source)
                        save_data_sources(st.session_state.data_sources)
                        st.success(f"✅ Added: {media_count['images']} images, {media_count['videos']} videos found")
                        st.rerun()
                    else:
                        st.error(f"❌ Folder not found: {folder_path}")
                else:
                    st.warning("Please enter a folder path")
    
    with tab2:
        st.subheader("Upload Files")
        st.info("Upload images directly. They will be saved to the 'uploads' folder.")
        
        uploaded_files = st.file_uploader(
            "Choose images or videos",
            type=['jpg', 'jpeg', 'png', 'bmp', 'webp', 'mp4', 'avi', 'mkv', 'mov', 'wmv', 'webm'],
            accept_multiple_files=True
        )
        
        if uploaded_files:
            upload_dir = Path(__file__).parent / "uploads"
            upload_dir.mkdir(exist_ok=True)
            
            # Show what files are queued
            st.write(f"**{len(uploaded_files)} files selected:**")
            for uf in uploaded_files:
                file_size = len(uf.getvalue()) / (1024 * 1024)  # MB
                st.write(f"  - {uf.name} ({file_size:.1f} MB)")
            
            if st.button("💾 Save & Add to Sources", type="primary"):
                saved_count = 0
                image_count = 0
                video_count = 0
                image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp', '.gif'}
                video_extensions = {'.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm'}
                
                progress = st.progress(0)
                status = st.empty()
                
                for idx, uploaded_file in enumerate(uploaded_files):
                    file_path = upload_dir / uploaded_file.name
                    status.text(f"Saving {uploaded_file.name}...")
                    
                    with open(file_path, "wb") as f:
                        f.write(uploaded_file.getbuffer())
                    saved_count += 1
                    
                    ext = Path(uploaded_file.name).suffix.lower()
                    if ext in image_extensions:
                        image_count += 1
                    elif ext in video_extensions:
                        video_count += 1
                    
                    progress.progress((idx + 1) / len(uploaded_files))
                
                # Add or update uploads folder as source
                upload_source_idx = next((i for i, s in enumerate(st.session_state.data_sources) if s["path"] == str(upload_dir)), None)
                
                if upload_source_idx is not None:
                    # Update existing source
                    st.session_state.data_sources[upload_source_idx]["images"] += image_count
                    st.session_state.data_sources[upload_source_idx]["videos"] += video_count
                    st.session_state.data_sources[upload_source_idx]["processed"] = False
                else:
                    # Create new source
                    new_source = {
                        "path": str(upload_dir),
                        "name": "Uploaded Files",
                        "include_subfolders": False,
                        "process_videos": True,  # Enable video processing
                        "added_at": datetime.now().isoformat(),
                        "processed": False,
                        "images": image_count,
                        "videos": video_count
                    }
                    st.session_state.data_sources.append(new_source)
                
                save_data_sources(st.session_state.data_sources)
                st.success(f"✅ Saved {image_count} images and {video_count} videos to {upload_dir}")
                st.rerun()
    
    st.markdown("---")
    
    # Show existing data sources
    st.subheader("📋 Configured Data Sources")
    
    if not st.session_state.data_sources:
        st.info("No data sources configured yet. Add a folder or upload files above.")
    else:
        for i, source in enumerate(st.session_state.data_sources):
            with st.container():
                col1, col2, col3 = st.columns([3, 1, 1])
                
                with col1:
                    status_icon = "✅" if source.get("processed") else "⏳"
                    st.markdown(f"""
                    **{status_icon} {source['name']}**  
                    📂 `{source['path']}`  
                    🖼️ {source.get('images', 0)} images | 🎬 {source.get('videos', 0)} videos
                    """)
                
                with col2:
                    if st.button("🚀 Process", key=f"process_{i}"):
                        st.session_state.processing_source = i
                        st.rerun()
                
                with col3:
                    if st.button("🗑️ Remove", key=f"remove_{i}"):
                        st.session_state.data_sources.pop(i)
                        save_data_sources(st.session_state.data_sources)
                        st.rerun()
                
                st.markdown("---")
    
    # Processing section - same scanner the Gallery uses (faces + bodies + media index)
    if 'processing_source' in st.session_state:
        source_idx = st.session_state.processing_source
        source = st.session_state.data_sources[source_idx]

        st.subheader(f"🔄 Processing: {source['name']}")

        try:
            import gallery_page
            from library_scanner import collect_media

            files = collect_media(source['path'],
                                  source.get('include_subfolders', True),
                                  source.get('process_videos', True))
            if not files:
                st.warning("No photos or videos found in this folder.")
            else:
                summary, grouping = gallery_page.scan_with_ui(
                    db, [str(f) for f in files],
                    strictness=st.session_state.get("gal_strictness", "balanced"),
                    detect_bodies=bool(st.session_state.get("gal_detect_bodies", True)),
                )
                st.session_state.data_sources[source_idx]["processed"] = True
                save_data_sources(st.session_state.data_sources)
                st.success(f"✅ {summary.as_text()}")
                if grouping:
                    st.success(f"👥 {grouping.as_text()}")
                if st.button("👥 Open the Gallery", type="primary"):
                    navigate_to("gallery")
        except Exception as e:
            st.error(f"❌ Processing failed: {e}")
            import traceback
            st.code(traceback.format_exc())
        finally:
            st.session_state.pop('processing_source', None)


elif page == "👥 Gallery":
    # The whole page lives in gallery_page.py - people, the review queue, the
    # media library and insights. dashboard.py only hands it the shared bits.
    import gallery_page

    def _set_gallery_query(key: str, value):
        """Keep deep links (?page=gallery&view=...&person_id=...) in sync."""
        try:
            if value is None:
                if key in st.query_params:
                    del st.query_params[key]
            else:
                st.query_params[key] = value
        except Exception:
            pass

    _gallery_view_param = None
    try:
        _gallery_view_param = st.query_params.get("view") or st.query_params.get("mode")
    except Exception:
        pass

    gallery_page.render(
        db=db,
        navigate_to=navigate_to,
        data_sources=st.session_state.get("data_sources", []),
        set_query=_set_gallery_query,
        view_param=_gallery_view_param,
        person_param=get_gallery_person_param(st),
    )


elif page == "🎭 Reface":
    st.title("🎭 Reface")
    st.markdown("Swap faces using angle-matched facesets for best quality")
    
    # Initialize reface engine
    try:
        from reface_engine import RefaceEngine, Faceset
        reface_init_error = None
    except Exception as e:
        reface_init_error = str(e)
    
    if reface_init_error:
        st.error(f"❌ Reface engine initialization failed: {reface_init_error}")
        st.info("Check console for details.")
    else:
        # Main workflow tabs
        main_tab1, main_tab2, main_tab3, main_tab4 = st.tabs([
            "🔄 Quick Swap", 
            "📦 Build Faceset (Advanced)", 
            "📜 History / Results",
            "⚙️ Background Jobs"
        ])
        
        with main_tab3:
            st.markdown("### 📜 Reface History")
            
            output_dir = Path(__file__).parent / "reface_output"
            output_dir.mkdir(exist_ok=True)
            
            # Refresh button
            if st.button("🔄 Refresh List"):
                st.rerun()
            
            # List files
            files = sorted(list(output_dir.glob("*.jpg")) + list(output_dir.glob("*.jpeg")) + \
                          list(output_dir.glob("*.png")) + list(output_dir.glob("*.mp4")) + \
                          list(output_dir.glob("*.avi")), key=os.path.getmtime, reverse=True)
            
            if not files:
                st.info("No reface results found yet.")
            else:
                st.caption(f"Found {len(files)} result(s)")
                
                # Grid view
                cols = st.columns(3)
                for i, file_path in enumerate(files):
                    with cols[i % 3]:
                        st.markdown("---")
                        
                        is_video = file_path.suffix.lower() in ['.mp4', '.avi', '.mov', '.mkv']
                        
                        try:
                            if is_video:
                                # Try to show MP4 video
                                if file_path.suffix.lower() == '.mp4':
                                    st.video(str(file_path))
                                else:
                                    # For AVI/others: Generate and show thumbnail
                                    import cv2
                                    cap = cv2.VideoCapture(str(file_path))
                                    ret, frame = cap.read()
                                    cap.release()
                                    
                                    if ret:
                                        # Convert BGR to RGB
                                        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                                        st.image(frame, caption=f"Preview ({file_path.suffix})", width='stretch')
                                    else:
                                        st.warning(f"No preview for {file_path.suffix}")
                                    
                                    # Add "Convert to MP4" button
                                    if st.button("🔄 Convert to Playable MP4", key=f"conv_{i}"):
                                        with st.spinner("Converting..."):
                                            try:
                                                import subprocess
                                                from ffmpeg_utils import _ffmpeg_exe
                                                
                                                # Locate FFmpeg
                                                ffmpeg_exe = _ffmpeg_exe()
                                                
                                                mp4_path = file_path.with_suffix('.mp4')
                                                subprocess.run([
                                                    ffmpeg_exe, '-y', '-i', str(file_path),
                                                    '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
                                                    '-pix_fmt', 'yuv420p', str(mp4_path)
                                                ], check=True)
                                                file_path.unlink() # Remove old avi
                                                st.success("Converted! Refreshing...")
                                                st.rerun()
                                            except Exception as e:
                                                st.error(f"FFmpeg failed: {e}")
                            else:
                                st.image(str(file_path), width='stretch')
                        except Exception as e:
                            st.error(f"Error loading preview: {e}")
                        
                        st.caption(f"📅 {datetime.fromtimestamp(file_path.stat().st_mtime).strftime('%Y-%m-%d %H:%M')}")
                        st.caption(f"📁 {file_path.name}")
                        
                        # Actions
                        c1, c2 = st.columns(2)
                        with c1:
                            with open(file_path, "rb") as f:
                                st.download_button(
                                    "⬇️",
                                    data=f.read(),
                                    file_name=file_path.name,
                                    mime="video/mp4" if is_video else "image/jpeg",
                                    key=f"dl_{i}_{file_path.name}"
                                )
                        with c2:
                            if st.button("🗑️", key=f"del_{i}_{file_path.name}", help="Delete file"):
                                try:
                                    file_path.unlink()
                                    st.success("Deleted!")
                                    st.rerun()
                                except Exception as e:
                                    st.error(f"Delete failed: {e}")
        
        with main_tab1:
            st.markdown("### Quick Face Swap")
            
            # GPU Status Check
            try:
                import onnxruntime as ort
                providers = ort.get_available_providers()
                if 'CUDAExecutionProvider' in providers:
                    st.success(f"🚀 **GPU Accelerated** (NVIDIA CUDA detected)", icon="⚡")
                else:
                    st.warning(f"🐢 **CPU Mode** (Install onnxruntime-gpu for speed)", icon="🐢")
            except:
                pass

            st.info("Upload source person media and target media for face swapping with angle matching")
            
            col1, col2 = st.columns(2)
            
            with col1:
                st.markdown("#### 📤 Step 1: Source Person Media")
                
                # Tabbed Interface for Source Selection
                src_tab1, src_tab2 = st.tabs(["📂 Upload Files", "📚 Saved Facesets"])
                
                with src_tab1:
                    st.caption("Upload photos/videos of the person whose face you want to use")
                    
                    source_files = st.file_uploader(
                        "Upload source media (multiple allowed)",
                        type=['jpg', 'jpeg', 'png', 'mp4', 'avi', 'mkv', 'mov'],
                        accept_multiple_files=True,
                        key="source_media_upload"
                    )
                    
                    if source_files:
                        source_dir = Path(__file__).parent / "reface_uploads" / "source"
                        source_dir.mkdir(parents=True, exist_ok=True)
                        source_paths = []
                        for f in source_files:
                            path = source_dir / f.name
                            with open(path, "wb") as out:
                                out.write(f.getbuffer())
                            source_paths.append(str(path))
                        
                        st.session_state['reface_source_paths'] = source_paths
                        st.session_state['reface_source_mode'] = 'upload'
                        st.success(f"✅ {len(source_files)} source file(s) uploaded")
                        
                        # Show previews inside the correct tab
                        if source_files:
                            preview_cols = st.columns(min(3, len(source_files)))
                            for i, f in enumerate(source_files[:3]):
                                with preview_cols[i]:
                                    ext = Path(f.name).suffix.lower()
                                    if ext in ['.mp4', '.avi', '.mkv', '.mov']:
                                        st.video(source_paths[i])
                                    else:
                                        st.image(source_paths[i], width='stretch')
                            
                            if len(source_files) > 3:
                                st.caption(f"... and {len(source_files) - 3} more")

                with src_tab2:
                    st.info("Select a pre-built faceset for faster, consistent results.")
                    if 'reface_engine_instance' not in st.session_state:
                         st.session_state['reface_engine_instance'] = RefaceEngine(enable_enhancement=False)
                    engine = st.session_state['reface_engine_instance']
                    
                    facesets = engine.list_facesets()
                    if not facesets:
                        st.warning("No saved facesets found. Go to 'Build Faceset' tab to create one!")
                    else:
                        selected_fs = st.selectbox("Choose a Faceset:", facesets, key="quick_swap_fs_select")
                        
                        # Only set faceset mode when explicitly clicking "Use This Faceset"
                        if st.button("✅ Use This Faceset", key="use_faceset_btn", type="primary"):
                            st.session_state['reface_selected_faceset_name'] = selected_fs
                            st.session_state['reface_source_mode'] = 'faceset'
                            # Clear upload paths to avoid confusion
                            if 'reface_source_paths' in st.session_state:
                                del st.session_state['reface_source_paths']
                            st.rerun()
                        
                        # Show current selection status
                        if st.session_state.get('reface_source_mode') == 'faceset' and st.session_state.get('reface_selected_faceset_name') == selected_fs:
                            st.success(f"✅ Using faceset: {selected_fs}")
                        
                        # Show preview of selected faceset
                        if selected_fs:
                            try:
                                fs = engine.load_faceset_by_name(selected_fs)
                                if fs and fs.faces:
                                    st.caption(f"{len(fs.faces)} faces in this faceset")
                                    # Show up to 4 sample faces
                                    preview_faces = fs.faces[:4]
                                    cols = st.columns(len(preview_faces))
                                    for i, face in enumerate(preview_faces):
                                        with cols[i]:
                                            img = cv2.imread(face.image_path)
                                            if img is not None:
                                                bbox = face.bbox
                                                x1, y1, x2, y2 = [int(b) for b in bbox]
                                                pad = 15
                                                h, w = img.shape[:2]
                                                x1, y1 = max(0, x1-pad), max(0, y1-pad)
                                                x2, y2 = min(w, x2+pad), min(h, y2+pad)
                                                crop = img[y1:y2, x1:x2]
                                                crop_rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
                                                st.image(crop_rgb, width='stretch')
                            except:
                                pass
            
            with col2:
                st.markdown("#### 🎯 Step 2: Target Media")
                st.caption("Upload the photo/video where you want to swap faces")
                
                target_file = st.file_uploader(
                    "Upload target media",
                    type=['jpg', 'jpeg', 'png', 'mp4', 'avi', 'mkv', 'mov'],
                    key="target_media_upload"
                )
                
                if target_file:
                    target_dir = Path(__file__).parent / "reface_uploads" / "target"
                    target_dir.mkdir(parents=True, exist_ok=True)
                    
                    target_path = target_dir / target_file.name
                    with open(target_path, "wb") as out:
                        out.write(target_file.getbuffer())
                    
                    st.session_state['reface_target_path'] = str(target_path)
                    
                    ext = Path(target_file.name).suffix.lower()
                    is_video = ext in ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.webm']
                    st.session_state['reface_target_is_video'] = is_video
                    
                    if is_video:
                        # Video Trimming Options
                        video_duration = 0
                        video_fps = 0
                        video_frame_count = 0
                        try:
                            import cv2
                            cap = cv2.VideoCapture(str(target_path))
                            video_fps = cap.get(cv2.CAP_PROP_FPS)
                            video_frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
                            video_duration = video_frame_count / video_fps if video_fps > 0 else 0
                            cap.release()
                        except Exception as e:
                            pass

                        start_time = st.session_state.get('video_trim_start', 0.0)

                        try:
                            # Play the video starting at the selected time
                            st.video(str(target_path), start_time=int(start_time))
                        except Exception:
                            # Fallback if start_time isn't supported
                            st.video(str(target_path))
                        
                        if video_duration > 0:
                            st.markdown("**✂️ Video Trimming** (optional)")
                            st.caption(f"Video duration: {video_duration:.1f} seconds ({video_frame_count} frames @ {video_fps:.0f} FPS)")
                            
                            trim_col1, trim_col2 = st.columns(2)
                            with trim_col1:
                                start_time = st.number_input(
                                    "Start time (seconds)",
                                    min_value=0.0,
                                    max_value=max(0.0, video_duration - 0.1),
                                    value=float(st.session_state.get('video_trim_start', 0.0)),
                                    step=0.5,
                                    key="video_trim_start"
                                )
                            with trim_col2:
                                valid_max_end = max(0.1, float(video_duration))
                                valid_value_end = float(st.session_state.get('video_trim_end', video_duration))
                                if valid_value_end > valid_max_end:
                                    valid_value_end = valid_max_end
                                    
                                end_time = st.number_input(
                                    "End time (seconds)",
                                    min_value=0.1,
                                    max_value=valid_max_end,
                                    value=valid_value_end,
                                    step=0.5,
                                    key="video_trim_end"
                                )
                            
                            # Store in session state for backend
                            st.session_state['reface_video_start_time'] = start_time
                            st.session_state['reface_video_end_time'] = end_time
                            
                            # Show trim duration
                            trim_duration = end_time - start_time
                            if trim_duration > 0 and trim_duration < video_duration:
                                st.info(f"📐 Will process {trim_duration:.1f} seconds of video")
                    else:
                        st.image(str(target_path), width='stretch')
                    
                    st.success("✅ Target media uploaded")
                    
                    # Face detection for target
                    if st.button("🔍 Detect Faces", key="detect_target_faces"):
                        with st.spinner("Detecting faces..."):
                            try:
                                import cv2
                                from insightface.app import FaceAnalysis
                                
                                app = FaceAnalysis(name='buffalo_l')
                                app.prepare(ctx_id=0, det_size=(640, 640))
                                
                                if is_video:
                                    cap = cv2.VideoCapture(str(target_path))
                                    ret, frame = cap.read()
                                    cap.release()
                                else:
                                    frame = cv2.imread(str(target_path))
                                
                                if frame is not None:
                                    faces = app.get(frame)
                                    if faces:
                                        # Save face crops
                                        crops_dir = Path(__file__).parent / "reface_uploads" / "target_faces"
                                        crops_dir.mkdir(parents=True, exist_ok=True)
                                        
                                        detected = []
                                        for i, face in enumerate(faces):
                                            bbox = face.bbox.astype(int)
                                            x1, y1, x2, y2 = bbox
                                            pad = 15
                                            x1, y1 = max(0, x1 - pad), max(0, y1 - pad)
                                            x2, y2 = min(frame.shape[1], x2 + pad), min(frame.shape[0], y2 + pad)
                                            
                                            crop = frame[y1:y2, x1:x2]
                                            crop_path = crops_dir / f"target_face_{i}.jpg"
                                            cv2.imwrite(str(crop_path), crop)
                                            
                                            detected.append({
                                                'index': i,
                                                'crop_path': str(crop_path),
                                                'bbox': bbox.tolist()
                                            })
                                        
                                        st.session_state['quick_swap_target_faces'] = detected
                                        st.success(f"Found {len(faces)} face(s)!")
                                        st.rerun()
                                    else:
                                        st.warning("No faces detected")
                            except Exception as e:
                                st.error(f"Detection failed: {e}")
                    
                    # Show detected faces for selection
                    if 'quick_swap_target_faces' in st.session_state:
                        detected = st.session_state['quick_swap_target_faces']
                        
                        if 'quick_swap_selected_faces' not in st.session_state:
                            st.session_state['quick_swap_selected_faces'] = list(range(len(detected)))  # All selected by default
                        
                        st.markdown(f"**Select faces to swap ({len(detected)} found):**")
                        
                        cols = st.columns(min(4, len(detected)))
                        for i, face_info in enumerate(detected):
                            with cols[i % 4]:
                                if os.path.exists(face_info['crop_path']):
                                    st.image(face_info['crop_path'], width='stretch')
                                
                                selected = st.checkbox(
                                    f"Face {i+1}",
                                    value=i in st.session_state.get('quick_swap_selected_faces', []),
                                    key=f"quick_face_{i}"
                                )
                                
                                if selected and i not in st.session_state['quick_swap_selected_faces']:
                                    st.session_state['quick_swap_selected_faces'].append(i)
                                elif not selected and i in st.session_state['quick_swap_selected_faces']:
                                    st.session_state['quick_swap_selected_faces'].remove(i)
                        
                        # Select all / none buttons
                        col_a, col_b = st.columns(2)
                        with col_a:
                            if st.button("Select All", key="select_all_faces"):
                                st.session_state['quick_swap_selected_faces'] = list(range(len(detected)))
                                st.rerun()
                        with col_b:
                            if st.button("Select None", key="select_none_faces"):
                                st.session_state['quick_swap_selected_faces'] = []
                                st.rerun()
                        
                        selected_count = len(st.session_state.get('quick_swap_selected_faces', []))
                        st.caption(f"✓ {selected_count} face(s) will be swapped")
            
            st.markdown("---")
            
            # Step 3: Options and Execute
            has_source = (st.session_state.get('reface_source_mode') == 'faceset' and st.session_state.get('reface_selected_faceset_name')) or \
                         (st.session_state.get('reface_source_mode') == 'upload' and st.session_state.get('reface_source_paths'))
            
            if has_source and st.session_state.get('reface_target_path'):
                st.markdown("#### ⚙️ Step 3: Options & Execute")
                
                col1, col2, col3 = st.columns(3)
                with col1:
                    upscale = st.selectbox("Output quality", [1, 2, 4], index=1,
                                          format_func=lambda x: f"{x}x {'(original)' if x==1 else 'upscale'}")
                with col2:
                    use_angle_match = st.checkbox("Use angle matching", value=True,
                                                 help="Match source face angle to target for better results")
                with col3:
                    run_background = st.checkbox("🔄 Run in Background", value=False,
                                                help="Run job in background - continues even if you close the tab")
                
                # DFM Engine Selection (Advanced)
                with st.expander("🔧 Advanced: Swap Engine", expanded=False):
                    st.markdown("**Choose your face swap engine:**")
                    
                    swap_engine = st.radio(
                        "Engine",
                        ["InsightFace (Quick)", "DeepFaceLab DFM (Pro)"],
                        index=0,
                        help="InsightFace is faster. DFM provides higher quality if you have a trained model."
                    )
                    
                    if swap_engine == "DeepFaceLab DFM (Pro)":
                        try:
                            from dfm_engine import DFMEngine
                            
                            # Search for DFM models
                            available_dfms = DFMEngine.list_available_models()
                            
                            if available_dfms:
                                st.success(f"✅ Found {len(available_dfms)} DFM model(s)")
                                dfm_options = {m.name: m.path for m in available_dfms}
                                selected_dfm_name = st.selectbox(
                                    "Select DFM Model",
                                    list(dfm_options.keys())
                                )
                                
                                if selected_dfm_name:
                                    st.session_state['selected_dfm_path'] = dfm_options[selected_dfm_name]
                                    selected_model = next(m for m in available_dfms if m.name == selected_dfm_name)
                                    st.caption(f"Type: {selected_model.model_type} | Size: {selected_model.file_size_mb:.1f} MB")
                            else:
                                st.warning("⚠️ No .dfm models found.")
                                st.markdown("""
**To create a DFM model:**
1. Train a model in DeepFaceLab (SAEHD or AMP)
2. Export using: `6) export SAEHD as dfm.bat`
3. Place the `.dfm` file in the `models/` folder
                                """)
                                swap_engine = "InsightFace (Quick)"  # Fallback
                        except ImportError:
                            st.error("DFM engine not available. Using InsightFace.")
                            swap_engine = "InsightFace (Quick)"
                    
                    st.session_state['swap_engine_type'] = swap_engine
                

                # Check if faces were detected and selected
                target_face_indices = None
                if 'quick_swap_selected_faces' in st.session_state:
                    target_face_indices = st.session_state['quick_swap_selected_faces']
                    st.caption(f"ℹ️ Swapping {len(target_face_indices)} selected face(s)")
                else:
                    st.caption("ℹ️ No specific faces selected, will swap ALL faces found.")
                
                # Background job execution
                if run_background:
                    if st.button("🚀 Start Background Job", type="primary", width='stretch'):
                        try:
                            from job_manager import JobManager, add_job_to_queue
                            job_manager = JobManager()
                            
                            # Prepare job params
                            is_video = st.session_state.get('reface_target_is_video', False)
                            params = {
                                'target_path': st.session_state['reface_target_path'],
                                'is_video': is_video,
                                'upscale': upscale,
                                'use_angle_matching': use_angle_match,
                                'target_face_indices': target_face_indices
                            }
                            
                            # Add video trim parameters if available
                            if is_video:
                                params['start_time'] = st.session_state.get('reface_video_start_time', 0.0)
                                params['end_time'] = st.session_state.get('reface_video_end_time', None)
                            
                            if st.session_state.get('reface_source_mode') == 'faceset':
                                params['faceset_name'] = st.session_state['reface_selected_faceset_name']
                            else:
                                params['source_paths'] = st.session_state['reface_source_paths']
                            
                            # Add job to queue (starts worker if needed)
                            job_type = "reface_video" if is_video else "reface_image"
                            job = add_job_to_queue(job_type, params, str(job_manager.jobs_dir))
                            
                            if job.queue_position > 0:
                                st.success(f"✅ Job **{job.id}** added to queue (position {job.queue_position + 1})")
                                st.info("📌 Your job will start after the current job completes. Check **Background Jobs** tab for status.")
                            else:
                                st.success(f"✅ Job **{job.id}** started!")
                                st.info("📌 Check the **Background Jobs** tab or terminal for progress.")
                            
                        except Exception as e:
                            import traceback
                            st.error(f"Failed to start background job: {e}")
                            st.code(traceback.format_exc())
                else:
                    # Original synchronous execution
                    if st.button("🚀 Swap Faces", type="primary", width='stretch'):
                        with st.spinner("Processing..."):
                            try:
                                _dfm_sel = (st.session_state.get('swap_engine_type') == "DeepFaceLab DFM (Pro)"
                                            and st.session_state.get('selected_dfm_path'))
                                if _dfm_sel:
                                    from reface_engine_v3 import RefaceEngineV3
                                    engine = RefaceEngineV3(dfm_path=st.session_state['selected_dfm_path'])
                                    st.info(f"🧬 Using DeepFaceLab DFM: {Path(st.session_state['selected_dfm_path']).name}")
                                else:
                                    engine = RefaceEngine(upscale=upscale)

                                faceset = None
                                
                                # Determine source strategy
                                if st.session_state.get('reface_source_mode') == 'faceset':
                                    fs_name = st.session_state['reface_selected_faceset_name']
                                    st.text(f"Loading faceset '{fs_name}'...")
                                    faceset = engine.load_faceset_by_name(fs_name)
                                    if not faceset:
                                        st.error(f"Failed to load faceset: {fs_name}")
                                        st.stop()
                                else:
                                    # Build from uploaded files
                                    st.text("Building faceset from source media...")
                                    progress1 = st.progress(0)
                                    status1 = st.empty()
                                    eta_build = ETACalculator(len(st.session_state['reface_source_paths']))
                                    
                                    def update_build_progress(current, total):
                                        eta_str = eta_build.get_eta_string(current)
                                        progress1.progress(current / total)
                                        status1.text(f"Building faceset: {current}/{total} ({eta_str} remaining)...")
                                    
                                    faceset = engine.build_faceset_from_media(
                                        st.session_state['reface_source_paths'],
                                        faceset_name="quick_swap",
                                        progress_callback=update_build_progress
                                    )
                                
                                if not faceset or not faceset.faces:
                                    st.error("No faces found in source!")
                                else:
                                    st.success(f"✅ Built faceset with {len(faceset.faces)} faces")
                                    
                                    # Show coverage
                                    coverage = faceset.get_pose_coverage()
                                    st.caption(f"Coverage: Front={coverage['front']}, Left={coverage['left']}, Right={coverage['right']}, Up={coverage['up']}, Down={coverage['down']}")
                                    
                                    # Perform swap
                                    st.text("Swapping faces...")
                                    progress2 = st.progress(0)
                                    status_swap = st.empty()
                                    
                                    target_path = st.session_state['reface_target_path']
                                    is_video = st.session_state.get('reface_target_is_video', False)
                                    
                                    def update_swap_progress(current, total):
                                        if 'eta_swap' not in st.session_state or st.session_state.eta_swap_total != total:
                                            st.session_state.eta_swap = ETACalculator(total)
                                            st.session_state.eta_swap_total = total
                                            
                                        eta_str = st.session_state.eta_swap.get_eta_string(current)
                                        progress2.progress(current / total)
                                        status_swap.text(f"Swapping frames: {current}/{total} ({eta_str} remaining)...")
                                    
                                    if is_video:
                                        # Get trim parameters from session state
                                        video_start_time = st.session_state.get('reface_video_start_time', 0.0)
                                        video_end_time = st.session_state.get('reface_video_end_time', None)
                                        
                                        if _dfm_sel:
                                            result = engine.reface_video_v3(
                                                target_path,
                                                faceset,
                                                target_face_indices=target_face_indices,
                                                progress_callback=update_swap_progress,
                                                start_time=video_start_time,
                                                end_time=video_end_time,
                                            )
                                        else:
                                            result = engine.reface_video_with_faceset(
                                                target_path,
                                                faceset,
                                                target_face_indices=target_face_indices,
                                                use_angle_matching=use_angle_match,
                                                progress_callback=update_swap_progress,
                                                start_time=video_start_time,
                                                end_time=video_end_time
                                            )
                                    else:
                                        if _dfm_sel:
                                            result = engine.reface_image_v3(
                                                target_path,
                                                faceset,
                                                target_face_indices=target_face_indices,
                                            )
                                        else:
                                            result = engine.reface_with_faceset(
                                                target_path,
                                                faceset,
                                                target_face_indices=target_face_indices,
                                                use_angle_matching=use_angle_match
                                            )
                                        progress2.progress(1.0)
                                    
                                    if result.success:
                                        st.success(f"✅ {result.message}")
                                        
                                        if is_video and result.output_path:
                                            st.video(result.output_path)
                                        elif result.output_path:
                                            st.image(result.output_path, caption="Result")
                                        
                                        if result.output_path and os.path.exists(result.output_path):
                                            with open(result.output_path, "rb") as f:
                                                st.download_button(
                                                    "📥 Download Result",
                                                    data=f.read(),
                                                    file_name=Path(result.output_path).name,
                                                    mime="video/mp4" if is_video else "image/jpeg"
                                                )
                                    else:
                                        st.error(f"❌ {result.message}")
                            
                            except Exception as e:
                                st.error(f"❌ Error: {str(e)}")
                                import traceback
                                st.code(traceback.format_exc())
            else:
                st.info("👆 Upload both source and target media to continue")
        
        with main_tab2:
            st.markdown("### 📦 Build & Manage Facesets")
            st.info("Create named collections of faces (Facesets) from your photos and videos. Using a faceset improves reface quality by providing more angles.")
            
            # --- Documentation Section ---
            with st.expander("📚 How to Build a Professional Faceset", expanded=False):
                st.markdown("""
## Creating a High-Quality 3D Face Dataset

For **professional results**, your faceset should include faces from **multiple angles**. 
This allows the engine to match the source angle to the target pose for seamless swaps.

### 🎯 Required Angles (7-Point System)

| Priority | Angle | Yaw Range | How to Capture |
|----------|-------|-----------|----------------|
| 🔴 **Critical** | Front | -15° to +15° | Look directly at camera |
| 🟡 **Important** | Left 45° | -60° to -30° | Turn head slightly left |
| 🟡 **Important** | Right 45° | +30° to +60° | Turn head slightly right |
| 🟡 **Important** | Up | pitch > 15° | Tilt chin up slightly |
| 🟢 **Optional** | Left 90° | < -60° | Full profile shot (left side) |
| 🟢 **Optional** | Right 90° | > +60° | Full profile shot (right side) |
| 🟢 **Optional** | Down | pitch < -15° | Tilt chin down |

### 💡 Pro Tips

1. **Best Source Method**: Upload a **video of the person slowly turning their head** from left to right. 
   This captures all angles automatically in one go!

2. **Lighting**: Ensure even, soft lighting across all photos. Harsh shadows create artifacts.

3. **Resolution**: Higher resolution source = better quality swaps. Aim for at least 512px face size.

4. **Expressions**: Include:
   - Neutral expression (primary)
   - Slight smile
   - Eyes open naturally

5. **Quantity**: Target **50-200 faces** for optimal angle coverage.

### ⚠️ Common Mistakes to Avoid

| ❌ Problem | ✅ Solution |
|-----------|------------|
| Only frontal photos | Add profile and angled shots |
| Harsh lighting/shadows | Use soft, even lighting |
| Low resolution | Use higher quality source images |
| Blurry images | Ensure sharp focus on face |
| Only one expression | Include neutral + smile |

### 📊 Quality Scoring

After building a faceset, you'll see:
- **Quality Score (0-100)**: Higher = better angle coverage
- **Grade (A+ to F)**: Quick assessment
- **Coverage Grid**: Shows which angles are captured
- **Suggestions**: What to add for improvement
                """)
            
            # --- Create New Faceset ---
            with st.expander("✨ Create New Faceset", expanded=True):

                col1, col2 = st.columns([1, 2])
                with col1:
                    new_faceset_name = st.text_input("Faceset Name", placeholder="e.g. MyFriend_John")
                with col2:
                    faceset_files = st.file_uploader("Upload Source Media", accept_multiple_files=True, type=['jpg', 'png', 'mp4', 'mov'])
                
                if st.button("🔨 Build & Save Faceset", disabled=not (new_faceset_name and faceset_files)):
                    if not new_faceset_name.strip():
                        st.error("Please provide a valid name.")
                    else:
                        # Save to PERMANENT faceset-specific directory
                        faceset_media_dir = Path(__file__).parent / "facesets" / new_faceset_name / "source_media"
                        faceset_media_dir.mkdir(parents=True, exist_ok=True)
                        
                        saved_paths = []
                        for uploaded_file in faceset_files:
                            path = faceset_media_dir / uploaded_file.name
                            with open(path, "wb") as f:
                                f.write(uploaded_file.getbuffer())
                            saved_paths.append(str(path))
                        
                        
                        progress_bar = st.progress(0)
                        status_text = st.empty()
                        
                        eta_build = ETACalculator(len(saved_paths))
                        def update_progress(current, total):
                            eta_str = eta_build.get_eta_string(current)
                            progress_bar.progress(current / total)
                            status_text.text(f"Processing media {current}/{total} ({eta_str} remaining)...")
                            
                        try:
                            # Build
                            if 'reface_engine_instance' not in st.session_state:
                                st.session_state['reface_engine_instance'] = RefaceEngine(enable_enhancement=True)
                            engine = st.session_state['reface_engine_instance']
                            
                            faceset = engine.build_faceset_from_media(
                                saved_paths, 
                                faceset_name=new_faceset_name,
                                progress_callback=update_progress
                            )
                            
                            # Save
                            engine.save_faceset(faceset)
                            
                            st.success(f"✅ Faceset '{new_faceset_name}' created with {len(faceset.faces)} faces!")
                            
                            # Show detailed coverage analysis
                            st.markdown("#### 📊 Faceset Quality Analysis")
                            
                            # Quality score and grade
                            quality_score = faceset.get_quality_score()
                            quality_grade = faceset.get_quality_grade()
                            
                            score_col1, score_col2 = st.columns(2)
                            with score_col1:
                                st.metric("Quality Score", f"{quality_score:.0f}/100")
                            with score_col2:
                                grade_emoji = {"A+": "🏆", "A": "⭐", "B": "👍", "C": "👌", "D": "⚠️", "F": "❌"}.get(quality_grade, "")
                                st.metric("Grade", f"{grade_emoji} {quality_grade}")
                            
                            # Detailed angle coverage
                            detailed_cov = faceset.get_detailed_coverage()
                            
                            st.markdown("**Angle Coverage:**")
                            angle_cols = st.columns(7)
                            angle_order = ['front', 'left_45', 'right_45', 'up', 'down', 'left_90', 'right_90']
                            angle_labels = {
                                'front': '🎯 Front', 'left_45': '↖️ Left 45°', 'right_45': '↗️ Right 45°',
                                'up': '⬆️ Up', 'down': '⬇️ Down', 'left_90': '⬅️ Left 90°', 'right_90': '➡️ Right 90°'
                            }
                            
                            for i, angle in enumerate(angle_order):
                                data = detailed_cov[angle]
                                with angle_cols[i]:
                                    count = data['count']
                                    priority = data['priority']
                                    color = "green" if count > 0 else ("red" if data['required'] else "gray")
                                    emoji = "✅" if count > 0 else ("❌" if data['required'] else "⬜")
                                    st.markdown(f"**{emoji}**")
                                    st.caption(f"{angle_labels.get(angle, angle)}")
                                    st.caption(f"{count} faces")
                            
                            # Suggestions
                            suggestions = faceset.get_suggestions()
                            if suggestions:
                                st.markdown("**💡 Suggestions:**")
                                for suggestion in suggestions:
                                    st.markdown(f"- {suggestion}")
                            
                        except Exception as e:
                            import traceback
                            st.error(f"Failed to build faceset: {e}")
                            st.code(traceback.format_exc())

            
            st.markdown("---")
            
            # --- Manage Existing Facesets ---
            st.subheader("📚 Your Facesets")
            
            if 'reface_engine_instance' not in st.session_state:
                 st.session_state['reface_engine_instance'] = RefaceEngine(enable_enhancement=False) # lightweight init
            
            engine = st.session_state['reface_engine_instance']
            facesets = engine.list_facesets()
            
            if not facesets:
                st.info("No saved facesets found.")
            else:
                for fs_name in facesets:
                    with st.container():
                        # Load faceset ONCE at start of container
                        loaded_fs = None
                        face_count = 0
                        preview_img = None
                        
                        try:
                            loaded_fs = engine.load_faceset_by_name(fs_name)
                            if loaded_fs and loaded_fs.faces:
                                face_count = len(loaded_fs.faces)
                                # Get first face's image and crop
                                first_face = loaded_fs.faces[0]
                                img = cv2.imread(first_face.image_path)
                                if img is not None:
                                    bbox = first_face.bbox
                                    x1, y1, x2, y2 = [int(b) for b in bbox]
                                    pad = 20
                                    h, w = img.shape[:2]
                                    x1, y1 = max(0, x1-pad), max(0, y1-pad)
                                    x2, y2 = min(w, x2+pad), min(h, y2+pad)
                                    crop = img[y1:y2, x1:x2]
                                    preview_img = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
                        except:
                            pass
                        
                        c1, c2, c3 = st.columns([1, 3, 1])
                        
                        with c1:
                            if preview_img is not None:
                                st.image(preview_img, width=80)
                            else:
                                st.markdown("🖼️")
                        
                        with c2:
                            st.markdown(f"**{fs_name}**")
                            if face_count > 0:
                                st.caption(f"{face_count} faces")
                        
                        with c3:
                            if st.button("🗑️", key=f"del_fs_{fs_name}"):
                                try:
                                    # Delete pkl file
                                    (engine.faceset_dir / f"{fs_name}.pkl").unlink()
                                    # Delete source media folder if exists
                                    import shutil
                                    media_dir = engine.faceset_dir / fs_name
                                    if media_dir.exists():
                                        shutil.rmtree(media_dir)
                                    st.success(f"Deleted {fs_name}")
                                    st.rerun()
                                except Exception as e:
                                    st.error(str(e))
        
        # Background Jobs Tab
        with main_tab4:
            st.markdown("### ⚙️ Background Jobs")
            st.info("Jobs run in the background and continue even if you close this tab. Check the terminal for real-time progress.")
            
            try:
                from job_manager import JobManager, JobStatus
                job_manager = JobManager()
                
                # Auto-refresh toggle
                col1, col2 = st.columns([3, 1])
                with col2:
                    if st.button("🔄 Refresh"):
                        st.rerun()
                
                jobs = job_manager.list_jobs(limit=20)
                
                if not jobs:
                    st.info("No jobs found. Start a reface operation to see jobs here!")
                else:
                    # Running jobs first
                    running_jobs = [j for j in jobs if j.status == JobStatus.RUNNING]
                    if running_jobs:
                        st.subheader("🔄 Currently Running")
                        for job in running_jobs:
                            with st.container():
                                col1, col2, col3 = st.columns([4, 1, 1])
                                with col1:
                                    st.markdown(f"**Job {job.id}** - {job.job_type}")
                                    st.progress(job.progress)
                                    st.caption(job.message)
                                    st.caption(f"Started: {job.started_at}")
                                with col2:
                                    if st.button("⏹️ Stop", key=f"stop_{job.id}", help="Pause this job"):
                                        job_manager.request_stop(job.id)
                                        st.warning("⏸️ Stop requested - job will pause at next frame")
                                        import time
                                        time.sleep(1)
                                        st.rerun()
                                with col3:
                                    if st.button("🗑️", key=f"del_running_{job.id}", help="Delete this job"):
                                        job_manager.request_stop(job.id)
                                        import time
                                        time.sleep(0.5)
                                        job_manager.delete_job(job.id)
                                        st.success("Job deleted")
                                        st.rerun()
                        st.markdown("---")
                    
                    # Paused jobs (can resume)
                    paused_jobs = [j for j in jobs if j.status == JobStatus.PAUSED]
                    if paused_jobs:
                        st.subheader("⏸️ Paused Jobs")
                        for job in paused_jobs:
                            with st.container():
                                col1, col2 = st.columns([4, 1])
                                with col1:
                                    st.markdown(f"**Job {job.id}** - {job.job_type}")
                                    st.progress(job.progress)
                                    st.caption(f"Paused at frame {job.last_frame}")
                                with col2:
                                    if st.button("▶️ Resume", key=f"resume_{job.id}"):
                                        job_manager.resume_job(job.id)
                                        # Start worker if not running
                                        from job_manager import start_queue_worker
                                        start_queue_worker(str(job_manager.jobs_dir))
                                        st.success("▶️ Job queued for resume!")
                                        st.rerun()
                        st.markdown("---")
                    
                    # Queued jobs (waiting in line)
                    from job_manager import JobStatus as JS
                    queued_jobs = [j for j in jobs if j.status in [JobStatus.PENDING, JS.QUEUED]]
                    if queued_jobs:
                        st.subheader("📋 Queue")
                        for i, job in enumerate(sorted(queued_jobs, key=lambda x: x.created_at)):
                            pos = i + 1
                            st.markdown(f"**#{pos}** Job {job.id} - {job.job_type}")
                        st.caption(f"{len(queued_jobs)} job(s) waiting")
                        st.markdown("---")
                    
                    # Completed/Failed jobs
                    finished_jobs = [j for j in jobs if j.status in [JobStatus.COMPLETED, JobStatus.FAILED]]
                    if finished_jobs:
                        st.subheader("✅ Completed Jobs")
                        for job in finished_jobs[:10]:  # Last 10
                            with st.container():
                                status_icon = "✅" if job.status == JobStatus.COMPLETED else "❌"
                                st.markdown(f"{status_icon} **Job {job.id}** - {job.job_type}")
                                st.caption(job.message)
                                
                                if job.result_path and Path(job.result_path).exists():
                                    col1, col2 = st.columns([3, 1])
                                    with col1:
                                        if job.result_path.endswith(('.mp4', '.avi')):
                                            st.video(job.result_path)
                                        else:
                                            st.image(job.result_path, width=200)
                                    with col2:
                                        with open(job.result_path, "rb") as f:
                                            st.download_button(
                                                "📥 Download",
                                                data=f.read(),
                                                file_name=Path(job.result_path).name,
                                                key=f"dl_job_{job.id}"
                                            )
                                
                                if job.error and job.status == JobStatus.FAILED:
                                    with st.expander("Show Error"):
                                        st.code(job.error)
                                
                                # Delete job button
                                if st.button("🗑️ Remove", key=f"del_job_{job.id}"):
                                    job_manager.delete_job(job.id)
                                    st.rerun()
                                
                                st.markdown("---")
            except Exception as e:
                st.error(f"Error loading jobs: {e}")
        
        st.markdown("---")
        st.markdown("### Or use Gallery Persons")
        
        # Keep original tabs for gallery-based workflow
        tab1, tab2 = st.tabs(["📤 Upload Target Media", "📁 From Data Sources"])
        
        with tab1:
            st.subheader("Upload Photo or Video to Reface")
            uploaded_media = st.file_uploader(
                "Choose a photo or video",
                type=['jpg', 'jpeg', 'png', 'mp4', 'avi', 'mkv', 'mov'],
                key="reface_upload"
            )
            
            if uploaded_media:
                # Save uploaded file temporarily
                upload_dir = Path(__file__).parent / "reface_uploads"
                upload_dir.mkdir(exist_ok=True)
                
                media_path = upload_dir / uploaded_media.name
                with open(media_path, "wb") as f:
                    f.write(uploaded_media.getbuffer())
                
                # Determine media type
                ext = Path(uploaded_media.name).suffix.lower()
                is_video = ext in ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.webm']
                
                # Preview
                st.markdown("##### 📸 Preview")
                if is_video:
                    st.video(str(media_path))
                    st.info(f"🎬 Video uploaded: {uploaded_media.name}")
                else:
                    try:
                        import PIL.Image as PILImage
                        img_preview = PILImage.open(media_path)
                        img_preview.thumbnail((400, 400))
                        st.image(img_preview, caption="Uploaded image")
                    except Exception:
                        st.image(str(media_path), caption="Uploaded image", use_container_width=True)
                
                st.session_state['reface_media_path'] = str(media_path)
                st.session_state['reface_is_video'] = is_video
        
        with tab2:
            st.subheader("Select from Data Sources")
            
            # Get all media from data sources
            all_media = []
            image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
            video_extensions = {'.mp4', '.avi', '.mkv', '.mov', '.wmv', '.webm'}
            
            for source in st.session_state.data_sources:
                folder = Path(source['path'])
                if folder.exists():
                    for f in folder.rglob('*') if source.get('include_subfolders', True) else folder.iterdir():
                        if f.is_file():
                            ext = f.suffix.lower()
                            if ext in image_extensions or ext in video_extensions:
                                all_media.append({
                                    'path': str(f),
                                    'name': f.name,
                                    'type': 'video' if ext in video_extensions else 'image'
                                })
            
            if all_media:
                media_options = {m['name']: m for m in all_media}
                selected_media_name = st.selectbox(
                    "Choose media file",
                    options=list(media_options.keys())
                )
                
                if selected_media_name:
                    selected_media = media_options[selected_media_name]
                    
                    if selected_media['type'] == 'video':
                        st.video(selected_media['path'])
                    else:
                        try:
                            import PIL.Image as PILImage
                            img_preview = PILImage.open(selected_media['path'])
                            img_preview.thumbnail((400, 400))
                            st.image(img_preview, caption=selected_media['name'])
                        except Exception:
                            st.image(selected_media['path'], use_container_width=True)
                    
                    if st.button("Use This Media", type="primary"):
                        st.session_state['reface_media_path'] = selected_media['path']
                        st.session_state['reface_is_video'] = selected_media['type'] == 'video'
                        st.success(f"Selected: {selected_media_name}")
            else:
                st.info("No media files in data sources. Add data sources or upload a file.")
        
        st.markdown("---")
        
        # Step 2: Detect and select target faces
        if 'reface_media_path' in st.session_state and st.session_state.get('reface_media_path'):
            media_path = st.session_state['reface_media_path']
            is_video = st.session_state.get('reface_is_video', False)
            
            st.subheader("🎯 Step 2: Select Faces to Swap")
            
            # Detect faces in the media
            if st.button("🔍 Detect Faces in Media", type="primary"):
                with st.spinner("Detecting faces..."):
                    try:
                        import cv2
                        from insightface.app import FaceAnalysis
                        
                        # Initialize face detector
                        app = FaceAnalysis(name='buffalo_l')
                        app.prepare(ctx_id=0, det_size=(640, 640))
                        
                        if is_video:
                            # For video, extract first frame
                            cap = cv2.VideoCapture(media_path)
                            ret, frame = cap.read()
                            cap.release()
                            if not ret:
                                st.error("Could not read video frame")
                                frame = None
                        else:
                            frame = cv2.imread(media_path)
                        
                        if frame is not None:
                            # Detect faces
                            faces = app.get(frame)
                            
                            if faces:
                                st.session_state['reface_detected_faces'] = []
                                
                                # Save face crops for display
                                face_crops_dir = Path(__file__).parent / "reface_uploads" / "face_crops"
                                face_crops_dir.mkdir(parents=True, exist_ok=True)
                                
                                for i, face in enumerate(faces):
                                    bbox = face.bbox.astype(int)
                                    x1, y1, x2, y2 = bbox
                                    
                                    # Add padding
                                    pad = 20
                                    x1 = max(0, x1 - pad)
                                    y1 = max(0, y1 - pad)
                                    x2 = min(frame.shape[1], x2 + pad)
                                    y2 = min(frame.shape[0], y2 + pad)
                                    
                                    face_crop = frame[y1:y2, x1:x2]
                                    crop_path = face_crops_dir / f"face_{i}.jpg"
                                    cv2.imwrite(str(crop_path), face_crop)
                                    
                                    st.session_state['reface_detected_faces'].append({
                                        'index': i,
                                        'bbox': bbox.tolist(),
                                        'crop_path': str(crop_path)
                                    })
                                
                                st.success(f"✅ Detected {len(faces)} faces!")
                                st.rerun()
                            else:
                                st.warning("No faces detected in the media")
                    except Exception as e:
                        st.error(f"Face detection failed: {e}")
                        import traceback
                        st.code(traceback.format_exc())
            
            # Display detected faces for selection
            if 'reface_detected_faces' in st.session_state and st.session_state['reface_detected_faces']:
                detected_faces = st.session_state['reface_detected_faces']
                
                st.markdown(f"**Found {len(detected_faces)} faces. Select which to swap:**")
                
                # Initialize selected faces
                if 'reface_selected_target_faces' not in st.session_state:
                    st.session_state['reface_selected_target_faces'] = []
                
                # Display faces in grid
                cols = st.columns(min(5, len(detected_faces)))
                for i, face_info in enumerate(detected_faces):
                    with cols[i % 5]:
                        if os.path.exists(face_info['crop_path']):
                            st.image(face_info['crop_path'], width='stretch')
                        
                        is_selected = i in st.session_state.get('reface_selected_target_faces', [])
                        
                        if st.checkbox(
                            f"Face {i+1}",
                            value=is_selected,
                            key=f"target_face_{i}"
                        ):
                            if i not in st.session_state['reface_selected_target_faces']:
                                st.session_state['reface_selected_target_faces'].append(i)
                        else:
                            if i in st.session_state['reface_selected_target_faces']:
                                st.session_state['reface_selected_target_faces'].remove(i)
                
                selected_count = len(st.session_state.get('reface_selected_target_faces', []))
                if selected_count > 0:
                    st.success(f"✅ Selected {selected_count} face(s) for swapping")
                else:
                    st.info("Select at least one face to swap, or leave empty to swap ALL faces")
                
                st.markdown("---")
                
                # Step 3: Person selection for face swap
                st.subheader("👤 Step 3: Select Person to Swap In")
                
                persons = get_all_persons()
                
                if not persons:
                    st.warning("No persons in gallery. Go to Gallery to process and assign faces first.")
                else:
                    # Display persons as selectable grid
                    cols = st.columns(5)
                    
                    if 'reface_selected_person' not in st.session_state:
                        st.session_state['reface_selected_person'] = None
                    
                    for i, person in enumerate(persons):
                        with cols[i % 5]:
                            faces = get_faces_for_person(person["id"], limit=1)
                            
                            # Thumbnail
                            if faces and faces[0]["image_path"] and os.path.exists(faces[0]["image_path"]):
                                st.image(faces[0]["image_path"], width='stretch')
                            else:
                                st.markdown("""
                                <div style="background: #333; border-radius: 10px; height: 80px; 
                                            display: flex; align-items: center; justify-content: center;">
                                    <span style="font-size: 30px;">👤</span>
                                </div>
                                """, unsafe_allow_html=True)
                            
                            # Selection button
                            is_selected = st.session_state.get('reface_selected_person') == person['id']
                            btn_type = "primary" if is_selected else "secondary"
                            
                            if st.button(
                                f"{'✅ ' if is_selected else ''}{person['name'][:12]}",
                                key=f"select_person_{person['id']}",
                                type=btn_type,
                                width='stretch'
                            ):
                                st.session_state['reface_selected_person'] = person['id']
                                st.rerun()
                            
                            st.caption(f"{person['face_count']} faces")
                    
                    st.markdown("---")
                    
                    # Execute reface
                    if st.session_state.get('reface_selected_person'):
                        selected_person = next((p for p in persons if p['id'] == st.session_state['reface_selected_person']), None)
                        
                        if selected_person:
                            st.success(f"✅ Selected: **{selected_person['name']}** for face swap")
                            
                            # Get faces for this person
                            person_faces = get_faces_for_person(selected_person['id'], limit=20)
                            face_paths = [f['image_path'] for f in person_faces if f['image_path'] and os.path.exists(f['image_path'])]
                            
                            # Enhancement options
                            col1, col2 = st.columns(2)
                            with col1:
                                upscale = st.selectbox("Output quality", [1, 2, 4], index=1, 
                                                      format_func=lambda x: f"{x}x {'(Original)' if x==1 else 'upscale'}")
                            with col2:
                                swap_all = st.checkbox("Swap ALL detected faces", value=len(st.session_state.get('reface_selected_target_faces', [])) == 0)
                            
                            if st.button("🚀 Start Face Swap", type="primary", width='stretch'):
                                if not face_paths:
                                    st.error("No face images found for this person")
                                else:
                                    with st.spinner("Processing face swap... This may take a while for videos."):
                                        try:
                                            engine = RefaceEngine(upscale=upscale)
                                            
                                            # Determine which faces to swap
                                            if swap_all:
                                                target_face_index = -1  # Swap all
                                            else:
                                                selected_indices = st.session_state.get('reface_selected_target_faces', [])
                                                # For now, swap first selected (could extend to multiple)
                                                target_face_index = selected_indices[0] if selected_indices else -1
                                            
                                            progress = st.progress(0)
                                            status = st.empty()
                                            
                                            def update_progress(current, total):
                                                if 'eta_gallery' not in st.session_state or st.session_state.eta_gallery_total != total:
                                                    st.session_state.eta_gallery = ETACalculator(total)
                                                    st.session_state.eta_gallery_total = total
                                                    
                                                eta_str = st.session_state.eta_gallery.get_eta_string(current)
                                                progress_pct = int((current / total) * 100) if total > 0 else 0
                                                progress.progress(current / total)
                                                status.text(f"Frame {current}/{total} ({progress_pct}%) ({eta_str} remaining)...")
                                            
                                            if is_video:
                                                result = engine.reface_video(
                                                    target_video_path=media_path,
                                                    source_person_faces=face_paths,
                                                    target_face_index=target_face_index,
                                                    progress_callback=update_progress
                                                )
                                            else:
                                                result = engine.reface_image(
                                                    target_image_path=media_path,
                                                    source_person_faces=face_paths,
                                                    target_face_index=target_face_index
                                                )
                                            
                                            if result.success:
                                                st.success(f"✅ {result.message}")
                                                
                                                # Show result
                                                if is_video and result.output_path:
                                                    st.video(result.output_path)
                                                elif result.output_path:
                                                    st.image(result.output_path, caption="Refaced Result")
                                                
                                                # Download button
                                                if result.output_path and os.path.exists(result.output_path):
                                                    with open(result.output_path, "rb") as f:
                                                        st.download_button(
                                                            "📥 Download Result",
                                                            data=f.read(),
                                                            file_name=Path(result.output_path).name,
                                                            mime="video/mp4" if is_video else "image/jpeg"
                                                        )
                                            else:
                                                st.error(f"❌ Face swap failed: {result.message}")
                                        
                                        except Exception as e:
                                            st.error(f"❌ Error: {str(e)}")
                                            import traceback
                                            st.code(traceback.format_exc())
                    else:
                        st.info("👆 Click on a person above to select them for face swap")
            else:
                st.info("👆 Click 'Detect Faces' to find faces in the media")



elif page == "✨ Magic Undress":
    st.title("✨ Magic Undress")
    st.markdown(
        "Clothes restyle: SegFormer finds the garment only, native SD 1.5 inpaint "
        "fills that hole (`padding_mask_crop`), then the result is pasted back onto "
        "the original photo so face, hair, arms, and background stay native-res."
    )

    if not VENV_AI_PYTHON.exists():
        st.error("AI environment not found (`venv_ai`).")
        st.markdown(SETUP_INSTRUCTIONS)
        st.stop()

    if "undress_image" not in st.session_state:
        st.session_state.undress_image = None
        st.session_state.undress_bbox = None
        st.session_state.undress_detected = False
        st.session_state.undress_upload_name = None
        st.session_state.undress_last_job_id = None

    col1, col2 = st.columns([1, 1])

    with col1:
        with st.container(border=True):
            st.markdown("##### 1. Source Image")
            source_mode = st.radio(
                "Source",
                ["Upload", "Gallery"],
                horizontal=True,
                key="undress_source_mode",
                help=UNDRESS_HELP["source"],
            )

            if source_mode == "Upload":
                uploaded_file = st.file_uploader(
                    "Upload Image",
                    type=["png", "jpg", "jpeg", "webp"],
                    key="undress_upload",
                    help=UNDRESS_HELP["upload"],
                )
                if uploaded_file is not None and st.session_state.undress_upload_name != uploaded_file.name:
                    st.session_state.undress_upload_name = uploaded_file.name
                    st.session_state.undress_image = Image.open(uploaded_file).convert("RGB")
                    st.session_state.undress_bbox = None
                    st.session_state.undress_detected = False
            else:
                persons = get_all_persons()
                if not persons:
                    st.info("No people in the gallery yet.")
                else:
                    person_id = st.selectbox(
                        "Person",
                        options=[p["id"] for p in persons],
                        format_func=lambda x: next(p["name"] for p in persons if p["id"] == x),
                        key="undress_gallery_person",
                    )
                    faces = [f for f in get_faces_by_person(person_id) if f.get("image_path")]
                    if not faces:
                        st.info("No saved faces for this person.")
                    else:
                        thumb_cols = st.columns(min(4, len(faces)))
                        for i, face in enumerate(faces[:8]):
                            with thumb_cols[i % len(thumb_cols)]:
                                if os.path.exists(face["image_path"]):
                                    st.image(face["image_path"], width='stretch')
                                if st.button("Use", key=f"undress_face_{face.get('id', i)}"):
                                    src = face.get("source_path") or ""
                                    ext = Path(src).suffix.lower()
                                    if ext in _IMAGE_EXTS and os.path.exists(src):
                                        st.session_state.undress_image = Image.open(src).convert("RGB")
                                        st.session_state.undress_upload_name = None
                                        st.session_state.undress_bbox = None
                                        st.session_state.undress_detected = False
                                        st.rerun()
                                    else:
                                        st.warning("This face was mined from a video or a missing file. Upload a still photo.")

        with st.container(border=True):
            st.markdown("##### 2. Generation Prompt")
            prompt = st.text_area("Prompt", DEFAULT_PROMPT, key="undress_prompt", help=UNDRESS_HELP["prompt"], height=100)
            neg_prompt = st.text_area(
                "Negative Prompt", DEFAULT_NEGATIVE_PROMPT, key="undress_neg_v5", help=UNDRESS_HELP["neg"], height=100
            )

        with st.container(border=True):
            st.markdown("##### 3. Generation Settings")
            col_a, col_b = st.columns(2)
            with col_a:
                steps = st.slider("Steps", 15, 50, 35, key="undress_steps_v3", help=UNDRESS_HELP["steps"])
                strength = st.slider("Inpaint strength", 0.3, 1.0, 0.95, step=0.05, key="undress_strength_v3", help=UNDRESS_HELP["strength"])
            with col_b:
                guidance = st.slider("Guidance", 3.0, 12.0, 7.5, step=0.5, key="undress_guidance", help=UNDRESS_HELP["guidance"])
                seed = st.number_input("Seed (-1 for random)", value=-1, step=1, key="undress_seed", help=UNDRESS_HELP["seed"])

        with st.container(border=True):
            st.markdown("##### 4. Advanced (Optional)")
            with st.expander("Reference Images & IP-Adapter"):
                ref_files = st.file_uploader(
                    "Garment / style references",
                    type=["png", "jpg", "jpeg", "webp"],
                    accept_multiple_files=True,
                    key="undress_refs",
                    help=UNDRESS_HELP["refs"],
                )
                ref_scale = st.slider(
                    "Reference strength", 0.0, 1.0, 0.6, step=0.05, key="undress_ref_scale", help=UNDRESS_HELP["ref_scale"],
                )

            with st.expander("High-Res Refine Pass"):
                refine = st.checkbox(
                    "Refine at native resolution", value=True, key="undress_refine", help=UNDRESS_HELP["refine"],
                )
                refine_strength = st.slider(
                    "Refine strength", 0.1, 0.6, 0.40, step=0.02, key="undress_refine_strength", help=UNDRESS_HELP["refine_strength"],
                )

        generate_btn = st.button("✨ Restyle Garment", type="primary", use_container_width=True)

    with col2:
        st.subheader("Preview / Result")

    input_image = st.session_state.undress_image
    if input_image is not None and not st.session_state.get("undress_detected"):
        with st.spinner("Detecting face..."):
            st.session_state.undress_bbox = detect_undress_subject(input_image)
            st.session_state.undress_detected = True

    if input_image is not None:
        preview = input_image
        if st.session_state.undress_bbox:
            preview = annotate_face_preview(input_image, st.session_state.undress_bbox)
            caption = "Green = kept (face, hair, arms, hands, skin, background). Red = clothes to restyle."
        else:
            caption = "No face found — clothes inpaint; already-exposed skin is still kept"
        with col1:
            st.image(preview, caption=caption, width='stretch')

    if generate_btn:
        if input_image is None:
            st.error("Upload or pick an image first.")
        else:
            INPUT_DIR.mkdir(parents=True, exist_ok=True)
            input_path = INPUT_DIR / f"{uuid.uuid4().hex[:10]}.png"
            input_image.save(input_path, format="PNG")
            ref_paths = []
            for ref_file in (ref_files or []):
                ref_path = INPUT_DIR / f"ref_{uuid.uuid4().hex[:10]}.png"
                Image.open(ref_file).convert("RGB").save(ref_path, format="PNG")
                ref_paths.append(str(ref_path))
            job = add_job_to_queue(
                "undress_image",
                {
                    "image_path": str(input_path),
                    "face_bbox": st.session_state.undress_bbox,
                    "prompt": prompt,
                    "negative_prompt": neg_prompt,
                    "seed": int(seed),
                    "steps": int(steps),
                    "strength": float(strength),
                    "guidance_scale": float(guidance),
                    "ref_images": ref_paths,
                    "ref_scale": float(ref_scale),
                    "refine": bool(refine),
                    "refine_strength": float(refine_strength),
                    "timeout": 7200,
                },
            )
            st.session_state.undress_last_job_id = job.id
            if job.queue_position > 0:
                st.success(f"Job {job.id} queued (position {job.queue_position + 1}).")
            else:
                st.success(f"Job {job.id} started. First run may download models (~5 GB).")

    job_manager = JobManager()
    undress_jobs = [j for j in job_manager.list_jobs(limit=20) if j.job_type == "undress_image"]
    with col2:
        show = None
        last_id = st.session_state.undress_last_job_id
        if last_id:
            show = job_manager.load_job(last_id)
        if show is None and undress_jobs:
            show = undress_jobs[0]
        if show is None:
            st.caption("Queue a job to see progress here. You can leave this page.")
        else:
            st.markdown(f"**Job {show.id}** — {show.status.value}")
            st.progress(min(max(show.progress, 0.0), 1.0))
            st.caption(show.message)
            if show.status == JobStatus.COMPLETED and show.result_path and os.path.exists(show.result_path):
                st.image(show.result_path, caption="Generated result", width='stretch')
                with open(show.result_path, "rb") as fh:
                    st.download_button(
                        "Download result",
                        fh.read(),
                        file_name=Path(show.result_path).name,
                        mime="image/png",
                        key=f"undress_dl_{show.id}",
                    )
                pose_path = Path(show.result_path).with_name(f"{show.id}_pose.png")
                mask_path = Path(show.result_path).with_name(f"{show.id}_mask.png")
                if mask_path.exists():
                    with st.expander("Inpaint mask (white = rewritten)"):
                        st.image(str(mask_path), caption="Model mask — original dress should be fully white")
                if pose_path.exists():
                    with st.expander("Pose debug"):
                        st.image(str(pose_path), caption="Detected pose")
            elif show.status == JobStatus.FAILED:
                st.error(show.message)
                if show.error:
                    with st.expander("Traceback"):
                        st.code(show.error)
            elif show.status in (JobStatus.RUNNING, JobStatus.QUEUED, JobStatus.PENDING):
                if st.button("Refresh status", key="undress_refresh"):
                    st.rerun()

        if undress_jobs:
            st.markdown("**Recent restyle jobs**")
            for job in undress_jobs[:8]:
                st.caption(f"{job.id} — {job.status.value} — {job.message}")


elif page == "🔀 Merge People":
    st.title("🔀 Merge People")
    st.markdown("Combine multiple person clusters into one")
    
    persons = get_all_persons()
    
    if len(persons) < 2:
        st.warning("Need at least 2 persons to merge")
    else:
        col1, col2 = st.columns(2)
        
        with col1:
            st.subheader("Source (will be deleted)")
            source_options = {f"{p['name']} ({p['face_count']} faces)": p['id'] for p in persons}
            source_selection = st.selectbox("Select source person", options=list(source_options.keys()))
            source_id = source_options[source_selection] if source_selection else None
            
            if source_id:
                faces = get_faces_for_person(source_id, limit=6)
                cols = st.columns(3)
                for i, face in enumerate(faces[:6]):
                    with cols[i % 3]:
                        if face["image_path"] and os.path.exists(face["image_path"]):
                            st.image(face["image_path"], width='stretch')
        
        with col2:
            st.subheader("Target (will receive faces)")
            target_options = {f"{p['name']} ({p['face_count']} faces)": p['id'] for p in persons if p['id'] != source_id}
            target_selection = st.selectbox("Select target person", options=list(target_options.keys()))
            target_id = target_options[target_selection] if target_selection else None
            
            if target_id:
                faces = get_faces_for_person(target_id, limit=6)
                cols = st.columns(3)
                for i, face in enumerate(faces[:6]):
                    with cols[i % 3]:
                        if face["image_path"] and os.path.exists(face["image_path"]):
                            st.image(face["image_path"], width='stretch')
        
        st.markdown("---")
        
        if source_id and target_id and source_id != target_id:
            if st.button("🔀 Merge Persons", type="primary", use_container_width=True):
                merge_persons(source_id, target_id)
                st.success("Persons merged successfully!")
                st.rerun()


elif page == "🧬 Character LoRA":
    st.title("🧬 Character LoRA")
    st.markdown("Build a face+body training set, train a per-person LoRA, and generate a clean reference portrait")

    tab_dataset, tab_train, tab_generate = st.tabs(["1) Dataset", "2) Train", "3) Generate"])

    persons = get_all_persons()

    with tab_dataset:
        source_mode = st.radio(
            "Source", ["📤 Upload New", "👥 Use Gallery Person"], horizontal=True, key="lora_dataset_source_mode",
            help="Upload New works like Reface V2's source upload: photos don't need to already be mined into a gallery person.",
        )

        build_clicked = False
        build_person_id = None
        build_person_name = None
        build_kind = None  # "upload" or "gallery"
        upload_paths = None

        if source_mode == "📤 Upload New":
            from lora_staging import (MEDIA_EXTENSIONS, clear_staged, import_folder, list_staged, move_staged,
                                      pick_folder, stage_bytes, staged_fingerprints, staging_dir, summarize_staging)

            character_name = st.text_input("Character Name", key="lora_upload_character_name")
            if "lora_upload_widget_key" not in st.session_state:
                st.session_state["lora_upload_widget_key"] = 0

            # The staging folder is the staged list, so nothing is lost on a refresh or a dropped connection.
            stage_dir = staging_dir(character_name)
            staged = list_staged(stage_dir)
            upload_paths = [str(p) for p in staged["images"] + staged["videos"]]

            notice = st.session_state.pop("lora_stage_notice", None)
            if notice:
                (st.warning if notice["result"].get("failed") else st.success)(summarize_staging(notice["result"]))
                for error in notice["result"].get("errors", [])[:10]:
                    st.caption(f"• {error}")

            if not character_name.strip():
                st.info("Type the character's name first — photos and videos are staged in a folder named after it.")
            else:
                st.markdown(f"**{len(staged['images'])} photo(s) and {len(staged['videos'])} video(s) staged**")
                st.caption(f"In `{stage_dir}`. They stay there until you clear them, even if the page reloads or "
                           "the dashboard restarts. Videos are sampled for face frames when you build the dataset.")

                earlier_dir = staging_dir("")
                earlier = list_staged(earlier_dir) if earlier_dir != stage_dir else {"images": [], "videos": []}
                earlier_count = len(earlier["images"]) + len(earlier["videos"])
                if earlier_count and st.button(f"📥 Add the {earlier_count} file(s) uploaded earlier without a name",
                                               help=f"Moves them here from `{earlier_dir}`."):
                    st.session_state["lora_stage_notice"] = {"result": move_staged(earlier_dir, stage_dir)}
                    st.rerun()

                add_mode = st.radio("Add photos & videos", ["📁 From a folder on this PC", "📤 Upload from the browser"],
                                    horizontal=True, key="lora_stage_add_mode")
                if add_mode == "📁 From a folder on this PC":
                    folder_col, browse_col = st.columns([5, 1], vertical_alignment="bottom")
                    # The button is handled before the text box exists this run, so it may still set the box's value.
                    if browse_col.button("📂 Browse…", width='stretch',
                                         help="Opens a folder picker on the PC running the dashboard."):
                        picked = pick_folder(st.session_state.get("lora_import_folder", ""))
                        if picked:
                            st.session_state["lora_import_folder"] = picked
                    import_source = folder_col.text_input("Folder", key="lora_import_folder",
                                                          placeholder=r"D:\Phone\DCIM\Camera").strip().strip('"')
                    import_recursive = st.checkbox("Include subfolders", value=True, key="lora_import_recursive")
                    st.caption("Best for big batches and long videos: files are read straight from disk, so there's "
                               "no upload to fail. Same-drive files are hard-linked (no extra space). Files already "
                               "staged are skipped, so running it again only adds what's new.")
                    if st.button("➕ Import", disabled=not import_source):
                        bar = st.progress(0.0, text="Scanning...")
                        try:
                            result = import_folder(import_source, stage_dir, recursive=import_recursive, progress=bar.progress)
                        except OSError as e:
                            bar.empty()
                            st.error(f"Couldn't import: {e}")
                        else:
                            print(f"[LORA_UPLOAD] {datetime.now().isoformat()} import {import_source} -> {stage_dir}: "
                                  f"{summarize_staging(result)}", flush=True)
                            if not result["found"] and not result["unsupported"]:
                                result["errors"] = [f"No photos or videos found in {import_source}"]
                            st.session_state["lora_stage_notice"] = {"result": result}
                            st.rerun()
                else:
                    st.caption("Fine for a few dozen photos. Files are only saved once the whole batch has arrived, "
                               "and a dropped connection stops the rest of the batch — for big batches or videos, "
                               "use **From a folder on this PC**. If a batch fails part-way, select the same files "
                               "again: the ones already staged are skipped.")
                    uploaded_files = st.file_uploader(
                        "Photos and videos", type=sorted(ext.lstrip(".") for ext in MEDIA_EXTENSIONS),
                        accept_multiple_files=True, key=f"lora_dataset_upload_{st.session_state['lora_upload_widget_key']}",
                    )
                    if uploaded_files:
                        result = {"added": 0, "duplicate": 0, "unsupported": 0, "failed": 0, "errors": []}
                        known = staged_fingerprints(stage_dir)
                        bar = st.progress(0.0, text=f"Saving 0/{len(uploaded_files)}...")
                        for i, uf in enumerate(uploaded_files):
                            try:
                                result[stage_bytes(stage_dir, uf.name, uf.getvalue(), known)] += 1
                            except OSError as e:
                                result["failed"] += 1
                                result["errors"].append(f"{uf.name}: {e}")
                            bar.progress((i + 1) / len(uploaded_files), text=f"Saving {i + 1}/{len(uploaded_files)}...")
                        print(f"[LORA_UPLOAD] {datetime.now().isoformat()} browser batch of {len(uploaded_files)} -> "
                              f"{stage_dir}: {summarize_staging(result)}", flush=True)
                        st.session_state["lora_stage_notice"] = {"result": result}
                        # A fresh, empty uploader so the next batch doesn't re-include these files.
                        st.session_state["lora_upload_widget_key"] += 1
                        st.rerun()

                if upload_paths:
                    with st.popover("🗑️ Clear staged files"):
                        st.write(f"Deletes the {len(upload_paths)} staged file(s) in `{stage_dir}`. "
                                 "Originals imported from a folder stay where they are.")
                        if st.button("Delete staged files", type="primary", key="lora_clear_staged"):
                            clear_staged(stage_dir)
                            st.rerun()

            if st.button("🛠️ Build Dataset", type="primary", disabled=not (character_name.strip() and upload_paths)):
                build_clicked = True
                build_kind = "upload"
                build_person_name = character_name
        else:
            if not persons:
                st.warning("No persons to build a dataset for. Add photos via Data Sources / Gallery first, or use Upload New above.")
            else:
                selected_person_id = st.selectbox(
                    "Person",
                    options=[p["id"] for p in persons],
                    format_func=lambda x: next(p["name"] for p in persons if p["id"] == x),
                    key="lora_dataset_person",
                )
                selected_person = next(p for p in persons if p["id"] == selected_person_id)
                face_count = len(get_faces_by_person(selected_person_id))
                st.caption(f"{face_count} saved face(s) for this person")

                if st.button("🛠️ Build Dataset", type="primary", key="lora_build_gallery"):
                    build_clicked = True
                    build_kind = "gallery"
                    build_person_id = selected_person_id
                    build_person_name = selected_person["name"]

        if build_clicked:
            with st.spinner("Building face+body dataset (restoring low-quality faces, auto-captioning)..."):
                if build_kind == "upload":
                    from database import add_person
                    from lora_dataset import build_dataset_from_uploads

                    existing = next((p for p in persons if p["name"].lower() == build_person_name.lower()), None)
                    build_person_id = existing["id"] if existing else add_person(build_person_name)
                    build_bar = st.progress(0.0, text="Finding faces...")
                    report = build_dataset_from_uploads(upload_paths, build_person_id, build_person_name, get_face_analyzer(),
                                                        progress=build_bar.progress)
                    build_bar.empty()
                else:
                    from lora_dataset import build_dataset

                    report = build_dataset(build_person_id, build_person_name, get_face_analyzer())
            st.session_state["lora_dataset_report"] = report

        report = st.session_state.get("lora_dataset_report")
        if report:
            if report["blocked"]:
                st.error(report["warning"])
            elif report["warning"]:
                st.warning(report["warning"])
            else:
                st.success(f"Built {report['image_count']} images in {report['dataset_dir']}")
            if report["skipped_body_count"]:
                st.info(f"{report['skipped_body_count']} item(s) had no body crop (video-sourced or missing source image) — face-only was used for those.")
            if report.get("video_count"):
                from lora_dataset import FRAMES_PER_VIDEO
                unreadable = (f" {report['unreadable_video_count']} couldn't be opened (unsupported codec?)."
                              if report.get("unreadable_video_count") else "")
                st.info(f"Sampled up to {FRAMES_PER_VIDEO} frames from each of {report['video_count']} video(s).{unreadable}")
            if report.get("skipped_no_face_count"):
                st.info(f"{report['skipped_no_face_count']} uploaded photo(s) or video frame(s) had no detectable face and were skipped.")

            dataset_dir = Path(report["dataset_dir"])
            image_files = sorted(dataset_dir.glob("*.jpg"))
            if image_files:
                st.markdown("**Review captions before training:**")
                rows = []
                for img_path in image_files:
                    caption_path = img_path.with_suffix(".txt")
                    rows.append({
                        "file": img_path.name,
                        "caption": caption_path.read_text(encoding="utf-8") if caption_path.exists() else "",
                    })
                edited = st.data_editor(rows, key="lora_caption_editor", width='stretch',
                                         column_config={"file": st.column_config.TextColumn(disabled=True)})
                if st.button("💾 Save Caption Edits"):
                    for row in edited:
                        (dataset_dir / row["file"]).with_suffix(".txt").write_text(row["caption"], encoding="utf-8")
                    st.success("Captions updated.")

    with tab_train:
        if not persons:
            st.info("Build a dataset in the first tab before training.")
        else:
            train_person_id = st.selectbox(
                "Person", options=[p["id"] for p in persons],
                format_func=lambda x: next(p["name"] for p in persons if p["id"] == x),
                key="lora_train_person",
            )
            train_person = next(p for p in persons if p["id"] == train_person_id)

            from lora_dataset import _slugify, DEFAULT_REPEATS
            from lora_trainer import (DEFAULT_EPOCHS, DEFAULT_NETWORK_DIM, DEFAULT_NETWORK_ALPHA, DEFAULT_LEARNING_RATE, DEFAULT_BATCH_SIZE,
                                      DEFAULT_MAX_RESOLUTION, RESOLUTION_OPTIONS, TARGET_TOTAL_STEPS, VENV_LORA_PYTHON, samples_per_epoch)

            slug = _slugify(train_person["name"])
            dataset_root = Path(__file__).parent / "lora_datasets" / slug
            dataset_subdirs = list(dataset_root.glob("*person")) if dataset_root.exists() else []

            if not dataset_subdirs:
                st.warning(f"No dataset found for {train_person['name']}. Build one in the Dataset tab first.")
            elif not VENV_LORA_PYTHON.exists():
                st.error("venv_lora not set up yet. See setup_venv_lora.bat (Task 10 of the implementation plan).")
            else:
                base_checkpoint_path = Path(__file__).parent / "models" / "sd15_realistic_base.safetensors"
                if not base_checkpoint_path.exists():
                    st.warning(f"Base checkpoint not found at {base_checkpoint_path}. Run: python download_models.py sd15_realistic_base")

                import math

                # train_data_dir is dataset_root, so sd-scripts trains every "{repeats}_..." folder in it.
                epoch_samples = samples_per_epoch(dataset_root)
                suggested_epochs = max(1, min(DEFAULT_EPOCHS, round(TARGET_TOTAL_STEPS / max(epoch_samples, 1))))

                epochs = st.number_input("Epochs", min_value=1, max_value=50, value=suggested_epochs)
                network_dim = st.number_input("Network Dim (rank)", min_value=4, max_value=128, value=DEFAULT_NETWORK_DIM)
                network_alpha = st.number_input("Network Alpha", min_value=1, max_value=128, value=DEFAULT_NETWORK_ALPHA)
                learning_rate = st.number_input("Learning Rate", min_value=0.00001, max_value=0.01, value=DEFAULT_LEARNING_RATE, format="%.5f")
                batch_size = st.number_input("Batch Size", min_value=1, max_value=4, value=DEFAULT_BATCH_SIZE)
                max_resolution = st.selectbox(
                    "Resolution", RESOLUTION_OPTIONS, index=RESOLUTION_OPTIONS.index(DEFAULT_MAX_RESOLUTION),
                    help="512 is SD1.5's native size. 768 has 2.25x the pixels per image, so every step is much slower.",
                )

                steps_per_epoch = math.ceil(epoch_samples / batch_size)
                st.caption(f"≈ {steps_per_epoch * epochs:,} training steps ({steps_per_epoch:,} per epoch × {epochs} epochs)")
                if epoch_samples * epochs > 2 * TARGET_TOTAL_STEPS:
                    st.warning(f"That's a very long run: a person LoRA is usually done within about {TARGET_TOTAL_STEPS:,} steps. "
                               "Consider fewer epochs.")

                if st.button("🚀 Start Training", type="primary"):
                    from job_manager import add_job_to_queue

                    job = add_job_to_queue("train_lora", {
                        "person_id": train_person_id,
                        "dataset_dir": str(dataset_subdirs[0]),
                        "output_dir": str(Path(__file__).parent / "models" / "loras"),
                        "output_name": slug,
                        "base_checkpoint": str(base_checkpoint_path),
                        "epochs": int(epochs), "network_dim": int(network_dim), "network_alpha": int(network_alpha),
                        "learning_rate": float(learning_rate), "batch_size": int(batch_size),
                        "max_resolution": int(max_resolution),
                    }, jobs_dir=str(Path(__file__).parent / "jobs"))
                    st.success(f"Training job queued: {job.id}")

            st.markdown("**Recent training jobs:**")
            from job_manager import JobManager as _JM, JobStatus as _JS, start_queue_worker
            from lora_trainer import (can_resume_training, latest_resume_state, read_log_tail, resume_training_job,
                                      training_log_path, training_run_dir, training_view)

            train_jobs_dir = str(Path(__file__).parent / "jobs")
            train_jobs = _JM(train_jobs_dir)
            person_names = {p["id"]: p["name"] for p in persons}

            def _fmt_duration(seconds):
                if seconds is None:
                    return "—"
                h, rem = divmod(int(max(seconds, 0)), 3600)
                m, s = divmod(rem, 60)
                return f"{h}h {m:02d}m" if h else (f"{m}m {s:02d}s" if m else f"{s}s")

            def _settings_line(p):
                return (f"{p.get('epochs')} epochs · dim {p.get('network_dim')} · alpha {p.get('network_alpha')} · "
                        f"lr {p.get('learning_rate')} · batch {p.get('batch_size')} · {p.get('max_resolution', 512)}px")

            def _training_active():
                # Poll only while a worker is alive to move a training job forward; a job nobody will
                # pick up never changes, and polling it would just rerun this panel forever.
                return train_jobs.is_worker_running() and any(
                    j.job_type == "train_lora" and j.status in (_JS.PENDING, _JS.QUEUED, _JS.RUNNING)
                    for j in train_jobs.list_jobs(limit=20))

            def _resume_controls(j):
                if not can_resume_training(j, train_jobs):
                    return
                saved = latest_resume_state(training_run_dir(j), j.params["output_name"])
                if saved is None:
                    st.caption("No finished epoch was saved for this run, so there's nothing to resume — start a new training instead.")
                elif st.button(f"▶️ Resume from epoch {saved[0] + 1}", key=f"resume_lora_{j.id}"):
                    resume_training_job(j, train_jobs)
                    start_queue_worker(train_jobs_dir)
                    st.rerun()

            def _render_running(j, who, view):
                p = j.params or {}
                with st.container(border=True):
                    st.markdown(f"🟢 **Training `{j.id}` — {who}**")
                    stage = view.get("stage") or j.message
                    stage_for = f" · for {_fmt_duration(view['stage_seconds'])}" if view.get("stage_seconds") is not None else ""
                    st.markdown(f"**Now:** {stage}{stage_for}")
                    if view.get("stage_total"):
                        st.progress(min(view["stage_done"] / view["stage_total"], 1.0),
                                    text=f"{view['stage_done']}/{view['stage_total']}")
                    st.progress(min(j.progress, 1.0), text=f"Overall {int(j.progress * 100)}% — {j.message}")

                    c1, c2, c3 = st.columns(3)
                    c1.metric("Epoch", f"{view['epoch']}/{view['total_epochs']}" if view.get("epoch") else "—")
                    if view.get("total_steps"):  # the total goes in the label: "3,010/3,060" is too wide for a third-width metric
                        c2.metric(f"Step (of {view['total_steps']:,})", f"{view['step']:,}")
                    else:
                        c2.metric("Step", "—")
                    c3.metric("Loss (avg)", f"{view['loss']:.4f}" if view.get("loss") is not None else "—")
                    c4, c5, c6 = st.columns(3)
                    c4.metric("Elapsed", _fmt_duration(view["elapsed_seconds"]))
                    eta = _fmt_duration(view["eta_seconds"]) if view["eta_seconds"] is not None else "—"
                    c5.metric("Time left", f"≈ {eta}" if view["eta_is_rough"] else eta)
                    c6.metric("Speed", f"{view['sec_per_step']:.2f} s/step" if view.get("sec_per_step") else "—")

                    idle = view["idle_seconds"]
                    if idle is not None and idle > 300:
                        st.warning(f"No sign of life from sd-scripts for {_fmt_duration(idle)}. Loading the model can take "
                                   "a minute or two, but this long usually means it's stuck — check the log below and "
                                   "the terminal running Streamlit.")
                    elif idle is not None:
                        st.caption(f"Last update {_fmt_duration(idle)} ago · refreshes every 2 s")
                    st.caption(f"Started {j.started_at[:19].replace('T', ' ')} · {_settings_line(p)}")
                    st.caption(f"Dataset: `{p.get('dataset_dir')}` · run folder: `{training_run_dir(j)}`")
                    if view["saved_files"]:
                        st.caption("Saved so far: " + ", ".join(f"{name} ({mb:.0f} MB)" for name, mb in view["saved_files"]))

                    with st.expander("📜 Training log (last 40 lines)"):
                        tail = read_log_tail(training_log_path(j))
                        if tail:
                            st.code(tail, language=None)
                        else:
                            st.caption("No log file for this run — it was started before the dashboard kept one, so "
                                       "its output only shows in the terminal running Streamlit.")

            def _render_queued(j, who, view, worker_alive):
                with st.container(border=True):
                    st.markdown(f"🕒 **Queued `{j.id}` — {who}**")
                    if not worker_alive:
                        st.error("The background worker isn't running, so this job won't start by itself "
                                 "(the dashboard or PC was probably restarted).")
                        if st.button("▶️ Start worker", key=f"start_worker_{j.id}"):
                            start_queue_worker(train_jobs_dir)
                            st.rerun()
                    else:
                        queued = train_jobs.get_queued_jobs()
                        ahead = next((i for i, q in enumerate(queued) if q.id == j.id), 0)
                        running = train_jobs.get_running_job()
                        if running is not None:
                            st.markdown(f"Waiting for job `{running.id}` ({running.job_type}) to finish first:")
                            st.progress(min(running.progress, 1.0), text=running.message)
                        elif ahead == 0:
                            st.caption("The worker is picking this job up...")
                        if ahead:
                            st.caption(f"{ahead} other queued job(s) run before this one.")
                    st.caption(f"Queued {_fmt_duration(view['queued_seconds'])} ago · {_settings_line(j.params or {})}")

            def _render_finished(j, who, view, expanded):
                p = j.params or {}
                interrupted = j.status == _JS.RUNNING
                icon = "⚠️" if interrupted else ("✅" if j.status == _JS.COMPLETED else "❌")
                label = "interrupted" if interrupted else j.status.value
                with st.expander(f"{icon} `{j.id}` — {who} — {label}", expanded=expanded):
                    st.write(j.message)
                    if interrupted:
                        st.warning("Still marked running, but no worker process is alive — the run was cut off "
                                   f"(dashboard or PC restarted?). Last sign of life {_fmt_duration(view['idle_seconds'])} ago.")
                    elif view["elapsed_seconds"] is not None:
                        st.caption(f"Ran for {_fmt_duration(view['elapsed_seconds'])} · started {(j.started_at or '')[:19].replace('T', ' ')}")
                    if j.status != _JS.COMPLETED and view.get("stage"):
                        st.caption(f"Stopped during: {view['stage']}")
                    st.caption(_settings_line(p))
                    if j.result_path:
                        st.caption(f"LoRA file: `{j.result_path}`")
                    if view["saved_files"]:
                        st.caption("Epoch snapshots: " + ", ".join(f"{name} ({mb:.0f} MB)" for name, mb in view["saved_files"]))
                    if j.error:
                        st.code(j.error, language=None)
                    _resume_controls(j)

            polling = _training_active()

            @st.fragment(run_every=2 if polling else None)
            def _training_jobs_panel():
                recent = [j for j in train_jobs.list_jobs(limit=20) if j.job_type == "train_lora"]
                if not recent:
                    st.caption("No training jobs yet.")
                worker_alive = train_jobs.is_worker_running()
                for i, j in enumerate(recent):
                    p = j.params or {}
                    who = person_names.get(p.get("person_id"), p.get("output_name", "?"))
                    view = training_view(j, train_jobs)
                    if j.status == _JS.RUNNING and worker_alive:
                        _render_running(j, who, view)
                    elif j.status in (_JS.PENDING, _JS.QUEUED):
                        _render_queued(j, who, view, worker_alive)
                    else:
                        _render_finished(j, who, view, expanded=(i == 0))
                if polling and not _training_active():
                    st.rerun()  # the run just ended: stop polling and let the Generate tab pick up the new LoRA

            _training_jobs_panel()

    with tab_generate:
        from database import get_person_lora_info

        trained_persons = [p for p in persons if get_person_lora_info(p["id"]).get("lora_path")]
        if not trained_persons:
            st.info("No trained LoRAs yet. Train one in the previous tab first.")
        else:
            from job_manager import JobManager as _JM, JobStatus as _JS, add_job_to_queue, start_queue_worker
            from lora_generate import (DEFAULT_PROMPT_TEMPLATE, DEFAULT_NEGATIVE_PROMPT, DEFAULT_REFERENCE_SCALE,
                                       DEFAULT_REFERENCE_STRENGTH, DEFAULT_GUIDANCE, DEFAULT_LORA_SCALE,
                                       REFERENCE_MODES, STAGE_GENERATING,
                                       denoising_steps, reference_mode, uses_img2img, uses_ip_adapter)
            from lora_generate_job import (build_generation_params, generation_log_path, generation_output_dir,
                                           generation_problems, generation_view, save_reference_image)
            from lora_trainer import read_log_tail

            gen_person_id = st.selectbox(
                "Person", options=[p["id"] for p in trained_persons],
                format_func=lambda x: next(p["name"] for p in trained_persons if p["id"] == x),
                key="lora_generate_person",
            )
            gen_person = next(p for p in trained_persons if p["id"] == gen_person_id)
            lora_info = get_person_lora_info(gen_person_id)

            default_prompt = DEFAULT_PROMPT_TEMPLATE.format(trigger=lora_info["trigger_word"])
            prompt = st.text_area("Prompt", default_prompt, key="lora_gen_prompt")
            negative_prompt = st.text_area("Negative Prompt", DEFAULT_NEGATIVE_PROMPT, key="lora_gen_negative")
            num_images = st.slider("Number of images", 1, 8, 4)
            seed = st.number_input("Seed (-1 for random)", value=-1, step=1, key="lora_gen_seed")
            multi_angle = st.checkbox("📐 Multi-angle set (Front, 3/4, Profile views)", value=True, key="lora_gen_multi_angle",
                                      help="Automatically varies poses across images (frontal, 3/4 left, 3/4 right, profile) so the reference set covers all angles.")

            c_scale1, c_scale2 = st.columns(2)
            with c_scale1:
                lora_scale = st.slider("LoRA Strength", 0.3, 1.2, DEFAULT_LORA_SCALE, 0.05, key="lora_gen_scale",
                                       help="0.75 - 0.85 preserves likeness without overpowering base photorealism.")
            with c_scale2:
                guidance_scale = st.slider("CFG Guidance", 2.0, 10.0, DEFAULT_GUIDANCE, 0.5, key="lora_gen_guidance",
                                           help="Realistic Vision works best at 4.0 - 5.5. Values above 7 cause oversaturated, burnt skin.")

            gen_reference = st.file_uploader(
                "Reference image (optional)", type=["png", "jpg", "jpeg", "webp"], key="lora_gen_reference",
                help="A photo for the images to follow. The face still comes from the person's LoRA.")
            # Just the choices here; the file itself is saved when the job is queued.
            gen_reference_params = {}
            if gen_reference is not None:
                ref_preview, ref_options = st.columns([1, 2])
                ref_preview.image(gen_reference, width='stretch')
                with ref_options:
                    ref_mode = st.radio(
                        "Follow the reference's", options=list(REFERENCE_MODES), format_func=REFERENCE_MODES.get,
                        horizontal=True, key="lora_gen_reference_mode",
                        help="**Pose & composition** starts each image from the reference (head angle, framing, "
                             "lighting, colours). **Style & look** borrows its look — hair, clothes, mood — without "
                             "copying the layout. **Both** does both.")
                    gen_reference_params = {"reference_image": gen_reference.name, "reference_mode": ref_mode}
                    if uses_img2img(gen_reference_params):
                        gen_reference_params["reference_strength"] = st.slider(
                            "Change from the reference", 0.3, 0.9, DEFAULT_REFERENCE_STRENGTH, 0.05,
                            key="lora_gen_reference_strength",
                            help="Lower stays closer to the reference's pose and colours; higher lets the prompt and "
                                 "the LoRA's face take over. Also fewer steps run at lower values.")
                    if uses_ip_adapter(gen_reference_params):
                        gen_reference_params["reference_scale"] = st.slider(
                            "Reference influence", 0.1, 1.0, DEFAULT_REFERENCE_SCALE, 0.05,
                            key="lora_gen_reference_scale",
                            help="How strongly IP-Adapter copies the reference's look. It copies the reference's "
                                 "face too, so above ~0.6 the person can stop looking like the LoRA.")
                        from undress_core import IP_ADAPTER_REPO_ID, IP_ADAPTER_SUBFOLDER, IP_ADAPTER_WEIGHT_NAME, hf_cache_snapshot
                        if hf_cache_snapshot(IP_ADAPTER_REPO_ID, f"{IP_ADAPTER_SUBFOLDER}/{IP_ADAPTER_WEIGHT_NAME}") is None:
                            st.caption("⬇️ The first run downloads the IP-Adapter and its image encoder (several GB).")

            gen_jobs_dir = str(Path(__file__).parent / "jobs")
            gen_jobs = _JM(gen_jobs_dir)
            gen_lora_file = Path(lora_info["lora_path"])
            gen_out_dir = generation_output_dir(gen_person["name"])

            gen_problems = generation_problems(lora_info, gen_person["name"])
            for problem in gen_problems:
                st.error(problem)
            if gen_lora_file.exists():
                st.caption(f"LoRA `{gen_lora_file.name}` ({gen_lora_file.stat().st_size / 2**20:.0f} MB) · trigger "
                           f"`{lora_info['trigger_word']}` · {denoising_steps(gen_reference_params)} steps per image · "
                           f"saves to `{gen_out_dir}`")

            if st.button("🎨 Generate Reference Images", type="primary", disabled=bool(gen_problems)):
                if gen_reference is not None:
                    gen_reference_params["reference_image"] = str(save_reference_image(gen_reference.getvalue(), gen_reference.name))
                add_job_to_queue("generate_lora_images",
                                 build_generation_params(gen_person, lora_info, num_images, seed=seed, prompt=prompt,
                                                         negative_prompt=negative_prompt,
                                                         reference_params=gen_reference_params,
                                                         lora_scale=lora_scale,
                                                         guidance_scale=guidance_scale,
                                                         multi_angle=multi_angle),
                                 jobs_dir=gen_jobs_dir)
                st.rerun()

            st.markdown("**Generation jobs** — these run in the background, so you can switch pages or close the tab.")

            def _gen_active():
                # Same rule as the training panel: only poll while a live worker can move a job forward.
                return gen_jobs.is_worker_running() and any(
                    j.job_type == "generate_lora_images" and j.status in (_JS.PENDING, _JS.QUEUED, _JS.RUNNING)
                    for j in gen_jobs.list_jobs(limit=100))

            def _gen_speed(sec_per_step):
                return f"{1 / sec_per_step:.2f} it/s" if sec_per_step < 1 else f"{sec_per_step:.2f} s/step"

            def _gen_images(images):
                if not images:
                    return
                cols = st.columns(4)
                for i, img in enumerate(images):
                    with cols[i % 4]:
                        if Path(img["path"]).exists():
                            st.image(img["path"], width='stretch')
                        else:
                            st.caption("(file was moved or deleted)")
                        vram = f" · {img['peak_vram_gb']:.1f} GB VRAM" if img.get("peak_vram_gb") else ""
                        st.caption(f"seed {img['seed']} · {img['seconds']:.0f}s{vram}")

            def _gen_settings_line(j, view):
                p = j.params or {}
                seed_text = f"seeds from {view['base_seed']}" if view.get("base_seed") is not None else (
                    "random seed" if p.get("seed", -1) == -1 else f"seeds from {p['seed']}")
                line = f"{p.get('num_images')} image(s) · {denoising_steps(p)} steps · {seed_text}"
                mode = reference_mode(p)
                if mode:
                    knobs = [f"change {p['reference_strength']:.2f}" if "reference_strength" in p else None,
                             f"influence {p['reference_scale']:.2f}" if "reference_scale" in p else None]
                    line += f" · follows reference ({REFERENCE_MODES.get(mode, mode).lower()}"
                    line += "".join(f", {k}" for k in knobs if k) + ")"
                return line

            def _gen_reference_thumb(p):
                if reference_mode(p) and Path(p["reference_image"]).exists():
                    st.image(p["reference_image"], width=96, caption="Reference")

            def _gen_startup_line(view):
                history = view.get("stage_history") or []
                return " · ".join(f"{stage} {_fmt_duration(seconds)}" for stage, seconds in history)

            def _gen_render_running(j, view):
                p = j.params or {}
                with st.container(border=True):
                    st.markdown(f"🟢 **Generating `{j.id}` — {p.get('person_name', '?')}**")
                    stage_for = f" · for {_fmt_duration(view['stage_seconds'])}" if view.get("stage_seconds") is not None else ""
                    st.markdown(f"**Now:** {view.get('stage')}{stage_for}")
                    total_images = view.get("total_images") or p.get("num_images") or 1
                    if view.get("stage") == STAGE_GENERATING and view.get("image", 0) > len(view["images"]):
                        st.progress(min(view["step"] / max(view["steps"], 1), 1.0),
                                    text=f"Image {view['image']}/{total_images} — step {view['step']}/{view['steps']}")
                    st.progress(min(view["steps_done"] / max(view["steps_total"], 1), 1.0),
                                text=f"Overall {int(view['steps_done'] / max(view['steps_total'], 1) * 100)}% — "
                                     f"{len(view['images'])}/{total_images} image(s) saved")

                    c1, c2, c3 = st.columns(3)
                    c1.metric("Images", f"{len(view['images'])}/{total_images}")
                    c2.metric("Speed", _gen_speed(view["sec_per_step"]) if view.get("sec_per_step") else "—")
                    c3.metric("Time left", _fmt_duration(view["eta_seconds"]) if view["eta_seconds"] is not None else "—")
                    c4, c5, c6 = st.columns(3)
                    c4.metric("Elapsed", _fmt_duration(view["elapsed_seconds"]))
                    device = view.get("device") or {}
                    c5.metric("GPU", f"{device['vram_gb']:.0f} GB" if device.get("vram_gb") else (device.get("device", "—").upper()),
                              help=device.get("gpu"))
                    c6.metric("Seed", view["base_seed"] if view.get("base_seed") is not None else "—")

                    idle = view["idle_seconds"]
                    if idle is not None and idle > 240:
                        st.warning(f"No sign of life from the generator for {_fmt_duration(idle)}. The first load of the "
                                   "checkpoint can take a minute or two, but this long usually means it's stuck — check the "
                                   "log below and the terminal running Streamlit.")
                    elif idle is not None:
                        st.caption(f"Last update {_fmt_duration(idle)} ago · refreshes every 2 s")
                    if device.get("device") == "cpu":
                        st.warning("venv_ai's torch can't see the GPU, so this runs on the CPU and will be very slow.")
                    if view.get("stage_history"):
                        st.caption(f"Startup: {_gen_startup_line(view)}")
                    st.caption(f"Started {j.started_at[:19].replace('T', ' ')} · {_gen_settings_line(j, view)}")

                    if gen_jobs.is_stop_requested(j.id):
                        st.caption("⏹️ Stopping — finished images are kept...")
                    elif st.button("⏹️ Stop", key=f"stop_gen_{j.id}"):
                        gen_jobs.request_stop(j.id)
                        st.rerun(scope="fragment")

                    _gen_reference_thumb(p)
                    _gen_images(view["images"])
                    with st.expander("📜 Log (last 40 lines)"):
                        tail = read_log_tail(generation_log_path(j, gen_jobs))
                        st.code(tail or "(nothing yet)", language=None)

            def _gen_render_queued(j, view, worker_alive):
                p = j.params or {}
                with st.container(border=True):
                    st.markdown(f"🕒 **Queued `{j.id}` — {p.get('person_name', '?')}**")
                    if not worker_alive:
                        st.error("The background worker isn't running, so this job won't start by itself "
                                 "(the dashboard or PC was probably restarted).")
                        if st.button("▶️ Start worker", key=f"start_gen_worker_{j.id}"):
                            start_queue_worker(gen_jobs_dir)
                            st.rerun()
                    else:
                        running = gen_jobs.get_running_job()
                        if running is not None:
                            st.markdown(f"Waiting for job `{running.id}` ({running.job_type}) to finish first:")
                            st.progress(min(running.progress, 1.0), text=running.message)
                        else:
                            st.caption("The worker is picking this job up...")
                    st.caption(f"Queued {_fmt_duration(view['queued_seconds'])} ago · {_gen_settings_line(j, view)}")
                    if st.button("✖️ Cancel", key=f"cancel_gen_{j.id}"):
                        fresh = gen_jobs.load_job(j.id)
                        if fresh and fresh.status in (_JS.PENDING, _JS.QUEUED):
                            fresh.status = _JS.FAILED
                            fresh.message = "✖️ Cancelled before it started"
                            fresh.completed_at = datetime.now().isoformat()
                            gen_jobs.save_job(fresh)
                        st.rerun()

            def _gen_render_finished(j, view, expanded):
                p = j.params or {}
                interrupted = j.status == _JS.RUNNING
                if interrupted:
                    icon, label = "⚠️", "interrupted"
                elif j.status == _JS.COMPLETED:
                    icon, label = "✅", "completed"
                elif (j.message or "")[:1] in ("⏹", "✖"):
                    icon, label = "⏹️", "stopped"
                else:
                    icon, label = "❌", "failed"
                total_images = p.get("num_images", "?")
                created = (j.created_at or "")[:16].replace("T", " ")
                with st.expander(f"{icon} `{j.id}` — {p.get('person_name', '?')} — {len(view['images'])}/{total_images} "
                                 f"image(s) — {label} — {created}", expanded=expanded):
                    st.write(j.message)
                    if interrupted:
                        st.warning("Still marked running, but no worker process is alive — the run was cut off "
                                   f"(dashboard or PC restarted?). Last sign of life {_fmt_duration(view['idle_seconds'])} ago. "
                                   "Images finished before that are kept.")
                    elif view["elapsed_seconds"] is not None:
                        st.caption(f"Ran for {_fmt_duration(view['elapsed_seconds'])} · started "
                                   f"{(j.started_at or '')[:19].replace('T', ' ')}")
                    if j.status != _JS.COMPLETED and view.get("stage"):
                        st.caption(f"Stopped during: {view['stage']}")
                    st.caption(_gen_settings_line(j, view))
                    if view.get("stage_history"):
                        st.caption(f"Startup: {_gen_startup_line(view)}")
                    if view.get("device", {}).get("gpu"):
                        st.caption(f"Ran on {view['device']['gpu']} ({view['device']['vram_gb']:.0f} GB) · torch {view['device']['torch']}")
                    st.caption(f"Prompt: {p.get('prompt', '')}")
                    _gen_reference_thumb(p)
                    _gen_images(view["images"])
                    if view["images"]:
                        st.caption(f"Saved in `{p.get('output_dir')}`")
                    if j.error:
                        st.code(j.error, language=None)
                    elif j.status != _JS.COMPLETED and generation_log_path(j, gen_jobs).exists():
                        st.code(read_log_tail(generation_log_path(j, gen_jobs), max_lines=25), language=None)

            gen_polling = _gen_active()

            @st.fragment(run_every=2 if gen_polling else None)
            def _generation_jobs_panel():
                recent = [j for j in gen_jobs.list_jobs(limit=100) if j.job_type == "generate_lora_images"][:6]
                if not recent:
                    st.caption("No generation jobs yet.")
                worker_alive = gen_jobs.is_worker_running()
                for i, j in enumerate(recent):
                    view = generation_view(j, gen_jobs)
                    if j.status == _JS.RUNNING and worker_alive:
                        _gen_render_running(j, view)
                    elif j.status in (_JS.PENDING, _JS.QUEUED):
                        _gen_render_queued(j, view, worker_alive)
                    else:
                        _gen_render_finished(j, view, expanded=(i == 0))
                if gen_polling and not _gen_active():
                    st.rerun()  # the run just ended: stop polling

            _generation_jobs_panel()


elif page == "🎭 Reface V2":
    st.title("🎭 Reface V2")
    st.markdown("**Professional face swapping** with neural enhancement, occlusion handling, and temporal consistency")
    
    # Initialize V2 engine
    try:
        from reface_engine_v2 import RefaceEngineV2, EnhancementConfig, OcclusionConfig, VideoConfig
        from reface_engine_v3 import RefaceEngineV3
        from reface_engine import Faceset
        reface_v2_error = None
    except Exception as e:
        reface_v2_error = str(e)
    
    if reface_v2_error:
        st.error(f"❌ Reface V2 engine initialization failed: {reface_v2_error}")
        st.code(reface_v2_error)
    else:
        # GPU Status
        try:
            import onnxruntime as ort
            providers = ort.get_available_providers()
            if 'CUDAExecutionProvider' in providers:
                st.success("🚀 **GPU Accelerated** (NVIDIA CUDA detected)", icon="⚡")
            else:
                st.warning("🐢 **CPU Mode** - Install onnxruntime-gpu for faster processing", icon="🐢")
        except:
            pass
        
        # V2 Features Info
        with st.expander("ℹ️ What's New in V2?", expanded=False):
            st.markdown("""
            **Reface V2** includes professional-grade enhancements:
            
            - **🧠 Neural Enhancement**: GFPGAN for high-quality face restoration
            - **🎭 Occlusion Handling**: Protects glasses, hands, and hair from being overwritten
            - **🎬 Temporal Consistency**: Reduces jitter in video face swaps
            - **🎨 Advanced Color Correction**: Skin-tone aware blending
            - **⚡ Quality Presets**: Fast, Standard, or Professional modes
            """)
        
        st.markdown("---")

        from job_manager import JobManager as _V2JM, JobStatus as _V2JS, gpu_heavy_job_running
        _v2_jobs = _V2JM(str(Path(__file__).parent / "jobs"))
        _v2_gpu_job = gpu_heavy_job_running(_v2_jobs)
        if _v2_gpu_job:
            st.warning(f"⏳ `{_v2_gpu_job.job_type}` job `{_v2_gpu_job.id}` is using the GPU — foreground swaps "
                       "and identity builds are disabled until it finishes (background swaps will queue behind it).")

        tab_v2_swap, tab_v2_build, tab_v2_dfl, tab_v2_history, tab_v2_jobs = st.tabs([
            "🔄 Quick Swap (V2)",
            "📦 Build Faceset (Advanced)",
            "🧠 Video Model (DFL)",
            "📜 History / Results",
            "⚙️ Background Jobs"
        ])
        
        with tab_v2_swap:
            # Main configuration
            col1, col2 = st.columns(2)
            
            with col1:
                with st.container(border=True):
                    st.markdown("#### 👤 Step 1: Source Face")
                st.caption("Upload the person's face you want to insert")
                
                # Source mode selection
                source_mode = st.radio("Source Mode", ["📤 Upload New", "📦 Use Faceset", "🧬 Trained LoRA"],
                                       horizontal=True, key="v2_source_mode")

                if source_mode == "📤 Upload New":
                    source_files = st.file_uploader(
                        "Upload source images/videos",
                        type=['jpg', 'jpeg', 'png', 'mp4', 'avi', 'mkv', 'mov'],
                        accept_multiple_files=True,
                        key="v2_source_upload"
                    )
                    
                    if source_files:
                        source_dir = Path(__file__).parent / "reface_uploads" / "v2_source"
                        source_dir.mkdir(parents=True, exist_ok=True)
                        
                        saved_paths = []
                        for sf in source_files:
                            fpath = source_dir / sf.name
                            with open(fpath, "wb") as out:
                                out.write(sf.getbuffer())
                            saved_paths.append(str(fpath))
                        
                        st.session_state['v2_source_paths'] = saved_paths
                        st.session_state['v2_data_source_mode'] = 'upload'
                        
                        # Preview
                        st.markdown("##### 📸 Source Previews")
                        import PIL.Image as PILImage
                        cols = st.columns(min(3, len(source_files)))
                        for i, sf in enumerate(source_files[:3]):
                            with cols[i]:
                                if sf.type.startswith('image'):
                                    try:
                                        img_source = PILImage.open(sf)
                                        img_source.thumbnail((200, 200))
                                        st.image(img_source, use_container_width=True)
                                    except:
                                        st.image(sf, use_container_width=True)
                        
                        st.success(f"✅ {len(source_files)} source file(s) ready")
                
                elif source_mode == "📦 Use Faceset":
                    faceset_dir = Path(__file__).parent / "facesets"
                    if faceset_dir.exists():
                        facesets = sorted([f.stem for f in faceset_dir.glob("*.pkl")])
                    else:
                        facesets = []
                    
                    if facesets:
                        selected_fs = st.selectbox("Select Faceset", facesets, key="v2_faceset_select")
                        
                        if selected_fs:
                            from reface_engine import Faceset
                            fs_data = None
                            path = faceset_dir / f"{selected_fs}.pkl"
                            if path.exists():
                                try:
                                    fs_data = Faceset.load(path)
                                except Exception as e:
                                    st.error(f"Failed to load faceset: {e}")
                                    
                            if fs_data and fs_data.faces:
                                first_face = fs_data.faces[0]
                                if getattr(first_face, 'image_path', None) and os.path.exists(first_face.image_path):
                                    st.markdown("##### 📸 Faceset Preview")
                                    try:
                                        import PIL.Image as PILImage
                                        img_preview = PILImage.open(first_face.image_path)
                                        img_preview.thumbnail((200, 200))
                                        st.image(img_preview, caption=f"Face from {selected_fs}")
                                    except Exception:
                                        st.image(first_face.image_path, caption=f"Face from {selected_fs}", width=200)

                        if st.button("✅ Use This Faceset", key="v2_use_faceset", use_container_width=True):
                            st.session_state['v2_selected_faceset'] = selected_fs
                            st.session_state['v2_data_source_mode'] = 'faceset'
                            st.success(f"Using faceset: {selected_fs}")
                    else:
                        st.info("No facesets found. Create one in the original Reface tab.")

                else:  # 🧬 Trained LoRA
                    from database import get_person_lora_info as _v2_get_lora_info
                    from lora_generate_job import build_generation_params, generation_problems
                    from lora_identity import (MODE_LABELS, MODE_LORA, MODE_MIXED, MODE_REAL, build_lora_faceset,
                                               clean_generated_images, real_photo_embeddings)

                    lora_persons = [p for p in get_all_persons() if _v2_get_lora_info(p["id"]).get("lora_path")]
                    if not lora_persons:
                        st.info("No persons with a trained LoRA yet.")
                        if st.button("🧬 Open Character LoRA", key="v2_lora_goto_train"):
                            navigate_to("🧬 Character LoRA")
                    else:
                        lora_person_id = st.selectbox(
                            "Person", options=[p["id"] for p in lora_persons],
                            format_func=lambda x: next(p["name"] for p in lora_persons if p["id"] == x),
                            key="v2_lora_person",
                        )
                        lora_v2_person = next(p for p in lora_persons if p["id"] == lora_person_id)
                        lora_v2_info = _v2_get_lora_info(lora_person_id)
                        lora_v2_file = Path(lora_v2_info["lora_path"])

                        if not lora_v2_file.exists():
                            st.warning(f"The LoRA file for {lora_v2_person['name']} is missing: {lora_v2_file}")
                            if st.button("🧬 Open Character LoRA", key="v2_lora_goto_missing"):
                                navigate_to("🧬 Character LoRA")

                        face_app_v2 = get_face_analyzer()
                        real_faces_preview, real_source_preview = real_photo_embeddings(
                            lora_person_id, lora_v2_person["name"], face_app_v2)

                        if not real_faces_preview:
                            st.error("No real photos found for this person, so generated faces can't be checked "
                                     "against them. Add photos to the gallery or build a training dataset first.")
                        else:
                            st.caption(f"{len(real_faces_preview)} real photo(s) available ({real_source_preview}).")

                            identity_from = st.radio(
                                "Identity from", [MODE_REAL, MODE_LORA, MODE_MIXED], format_func=MODE_LABELS.get,
                                horizontal=True, key="v2_lora_identity_from",
                                help="Real photos is the safe default until Phase 0 (see the LoRA-identity design "
                                     "doc) confirms whether LoRA portraits or a mix builds a stronger identity.",
                            )

                            selected_portrait_paths = []
                            if identity_from in (MODE_LORA, MODE_MIXED):
                                portrait_paths, excluded_portraits = clean_generated_images(
                                    lora_v2_person["name"], _v2_jobs)

                                st.markdown("##### 🖼️ Portraits")
                                if portrait_paths:
                                    port_cols = st.columns(4)
                                    for i, p in enumerate(portrait_paths):
                                        with port_cols[i % 4]:
                                            st.image(str(p), use_container_width=True)
                                            if st.checkbox("Use", value=True,
                                                          key=f"v2_lora_portrait_{lora_person_id}_{p.name}"):
                                                selected_portrait_paths.append(str(p))
                                else:
                                    st.caption("No clean generated portraits yet.")
                                if excluded_portraits:
                                    with st.expander(f"Excluded ({len(excluded_portraits)})"):
                                        for p, reason in excluded_portraits:
                                            st.caption(f"{p.name}: {reason}")

                                gen_problems_v2 = generation_problems(lora_v2_info, lora_v2_person["name"])
                                if st.button("🎨 Generate 8 portraits", key="v2_lora_generate_btn",
                                            disabled=bool(gen_problems_v2) or bool(_v2_gpu_job)):
                                    from job_manager import add_job_to_queue as _v2_add_job_to_queue
                                    _v2_add_job_to_queue(
                                        "generate_lora_images",
                                        build_generation_params(lora_v2_person, lora_v2_info, 8),
                                        jobs_dir=str(Path(__file__).parent / "jobs"))
                                    st.rerun()
                                for problem in gen_problems_v2:
                                    st.caption(f"⚠️ {problem}")

                                def _v2_lora_gen_jobs():
                                    return [j for j in _v2_jobs.list_jobs(limit=50)
                                           if j.job_type == "generate_lora_images"
                                           and (j.params or {}).get("person_id") == lora_person_id
                                           and j.status in (_V2JS.PENDING, _V2JS.QUEUED, _V2JS.RUNNING)]

                                _lora_polling = _v2_jobs.is_worker_running() and bool(_v2_lora_gen_jobs())

                                @st.fragment(run_every=2 if _lora_polling else None)
                                def _v2_lora_generation_status():
                                    pending = _v2_lora_gen_jobs()
                                    if pending:
                                        j = pending[0]
                                        running = _v2_jobs.get_running_job()
                                        if running is not None and running.id != j.id:
                                            st.caption(f"Waiting for job `{running.id}` ({running.job_type}) to finish")
                                        else:
                                            st.caption(j.message)
                                    if _lora_polling and not pending:
                                        st.rerun()  # the run just ended: refresh the portrait grid

                                _v2_lora_generation_status()

                            if st.button("✅ Use This LoRA Identity", key="v2_use_lora_identity",
                                        use_container_width=True, disabled=bool(_v2_gpu_job)):
                                built_faceset, build_report = build_lora_faceset(
                                    lora_v2_person, identity_from, selected_portrait_paths, face_app_v2, _v2_jobs)
                                if built_faceset is None:
                                    st.error(build_report.get("reason", "Could not build an identity."))
                                else:
                                    faceset_save_dir = Path(__file__).parent / "facesets"
                                    faceset_save_dir.mkdir(parents=True, exist_ok=True)
                                    built_faceset.save(faceset_save_dir / f"{built_faceset.name}.pkl")
                                    st.session_state['v2_selected_faceset'] = built_faceset.name
                                    st.session_state['v2_data_source_mode'] = 'faceset'
                                    message = f"`{built_faceset.name}` — {build_report.get('message', '')}"
                                    if len(built_faceset.faces) <= 2:
                                        st.warning(f"⚠️ Only {len(built_faceset.faces)} face(s) went into this "
                                                  f"identity. Using {message}")
                                    else:
                                        st.success(f"✅ Using {message}")
                            if _v2_gpu_job:
                                st.caption(f"Disabled while `{_v2_gpu_job.job_type}` job `{_v2_gpu_job.id}` "
                                          "is using the GPU.")

        with col2:
            with st.container(border=True):
                st.markdown("#### 🎯 Step 2: Target Media")
                st.caption("The photo/video where faces will be swapped")
                
                target_file = st.file_uploader(
                    "Upload target media",
                    type=['jpg', 'jpeg', 'png', 'mp4', 'avi', 'mkv', 'mov'],
                    key="v2_target_upload"
                )
                
                if target_file:
                    target_dir = Path(__file__).parent / "reface_uploads" / "v2_target"
                    target_dir.mkdir(parents=True, exist_ok=True)
                    
                    target_path = target_dir / target_file.name
                    with open(target_path, "wb") as out:
                        out.write(target_file.getbuffer())

                    if st.session_state.get('v2_target_path') != str(target_path):
                        # New target: faces detected and ticked on the old one no longer apply.
                        for k in [k for k in st.session_state.keys() if str(k).startswith('v2_target_face_')]:
                            del st.session_state[k]
                        st.session_state['v2_detected_faces'] = []
                        st.session_state['v2_selected_target_faces'] = []
                    st.session_state['v2_target_path'] = str(target_path)
                    
                    ext = Path(target_file.name).suffix.lower()
                    is_video = ext in ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.webm']
                    st.session_state['v2_is_video'] = is_video
                    
                    import PIL.Image as PILImage
                    
                    st.markdown("##### 📸 Preview")
                    if is_video:
                        st.video(str(target_path))
                    else:
                        try:
                            img_preview = PILImage.open(target_path)
                            img_preview.thumbnail((400, 400))
                            st.image(img_preview, caption=target_file.name)
                        except Exception:
                            st.image(str(target_path), use_container_width=True)
                    
                    st.success("✅ Target uploaded successfully")
                
                if 'v2_target_path' in st.session_state and st.session_state.get('v2_target_path'):
                    target_path_str = st.session_state['v2_target_path']
                    is_video_target = st.session_state.get('v2_is_video', False)
                    
                    # Detect faces in the media
                    if st.button("🔍 Detect Faces in Media", type="primary", key="v2_detect_btn", use_container_width=True):
                        with st.spinner("Detecting faces..."):
                            try:
                                import cv2

                                app = get_face_analyzer()  # cached; loading buffalo_l per click cost seconds

                                if is_video_target:
                                    # For video, extract first frame
                                    cap = cv2.VideoCapture(target_path_str)
                                    ret, frame = cap.read()
                                    cap.release()
                                    if not ret:
                                        st.error("Could not read video frame")
                                        frame = None
                                else:
                                    frame = cv2.imread(target_path_str)
                                
                                if frame is not None:
                                    # Detect faces
                                    faces = app.get(frame)
                                    
                                    if faces:
                                        st.session_state['v2_detected_faces'] = []
                                        st.session_state['v2_selected_target_faces'] = []
                                        for k in [k for k in st.session_state.keys()
                                                  if str(k).startswith('v2_target_face_')]:
                                            del st.session_state[k]

                                        # Save face crops for display
                                        face_crops_dir = Path(__file__).parent / "reface_uploads" / "v2_face_crops"
                                        face_crops_dir.mkdir(parents=True, exist_ok=True)
                                        
                                        for i, face in enumerate(faces):
                                            bbox = face.bbox.astype(int)
                                            x1, y1, x2, y2 = bbox
                                            
                                            # Add padding
                                            pad = 20
                                            x1 = max(0, x1 - pad)
                                            y1 = max(0, y1 - pad)
                                            x2 = min(frame.shape[1], x2 + pad)
                                            y2 = min(frame.shape[0], y2 + pad)
                                            
                                            face_crop = frame[y1:y2, x1:x2]
                                            crop_path = face_crops_dir / f"face_{i}.jpg"
                                            cv2.imwrite(str(crop_path), face_crop)
                                            
                                            st.session_state['v2_detected_faces'].append({
                                                'index': i,
                                                'bbox': bbox.tolist(),
                                                'crop_path': str(crop_path),
                                                # V3 finds the ticked people in every frame by
                                                # identity; detection order changes frame to frame.
                                                'embedding': [float(x) for x in face.normed_embedding],
                                            })
                                        
                                        st.success(f"✅ Detected {len(faces)} faces!")
                                        st.rerun()
                                    else:
                                        st.warning("No faces detected in the media")
                            except Exception as e:
                                st.error(f"Face detection failed: {e}")
                                import traceback
                                st.code(traceback.format_exc())
                    
                    # Display detected faces for selection
                    if 'v2_detected_faces' in st.session_state and st.session_state['v2_detected_faces']:
                        detected_faces = st.session_state['v2_detected_faces']
                        
                        st.markdown(f"**Found {len(detected_faces)} faces. Select which to swap:**")
                        
                        # Initialize selected faces
                        if 'v2_selected_target_faces' not in st.session_state:
                            st.session_state['v2_selected_target_faces'] = []
                        
                        # Display faces in grid
                        cols_faces = st.columns(min(5, len(detected_faces)))
                        for i, face_info in enumerate(detected_faces):
                            with cols_faces[i % 5]:
                                if os.path.exists(face_info['crop_path']):
                                    st.image(face_info['crop_path'], use_container_width=True)
                                
                                is_selected = i in st.session_state.get('v2_selected_target_faces', [])
                                
                                if st.checkbox(
                                    f"Face {i+1}",
                                    value=is_selected,
                                    key=f"v2_target_face_{i}"
                                ):
                                    if i not in st.session_state['v2_selected_target_faces']:
                                        st.session_state['v2_selected_target_faces'].append(i)
                                        st.rerun()
                                else:
                                    if i in st.session_state['v2_selected_target_faces']:
                                        st.session_state['v2_selected_target_faces'].remove(i)
                                        st.rerun()
                        
                        selected_count = len(st.session_state.get('v2_selected_target_faces', []))
                        if selected_count > 0:
                            st.info(f"✅ Selected {selected_count} face(s) for swapping")
                        else:
                            st.info("Select at least one face to swap, or leave empty to swap ALL faces.")
        
        st.markdown("---")
        
        # V2 Configuration Options
        with st.container(border=True):
            st.markdown("#### ⚙️ Step 3: Engine Options")

            engine_mode = st.radio(
                "Engine",
                ["✨ HD V3 (recommended)", "Legacy V2"],
                horizontal=True,
                help="HD V3: ONNX CodeFormer restoration + face-parser/occluder masks + averaged identity. "
                     "Sharper faces, stronger likeness, stable video. Legacy V2 kept for fallback.",
            )
            use_v3 = engine_mode.startswith("✨")

            if use_v3:
                vc1, vc2, vc3 = st.columns(3)
                with vc1:
                    from face_restore import RESTORER_FILES as _RESTORER_FILES, MODELS_DIR as _RESTORER_DIR
                    from reface_engine_v3 import DEFAULT_RESTORER as _DEFAULT_RESTORER
                    _restorer_opts = list(_RESTORER_FILES) + ["none"]
                    v3_restorer = st.selectbox(
                        "Restorer",
                        _restorer_opts,
                        index=_restorer_opts.index(_DEFAULT_RESTORER) if _DEFAULT_RESTORER in _restorer_opts else 0,
                        format_func=lambda n: n if n == "none" or (_RESTORER_DIR / _RESTORER_FILES[n]).exists()
                        else f"{n} (not downloaded - falls back to CodeFormer)",
                        help="CodeFormer best preserves identity. 'none' = swap only (no HD restore). "
                             "Optional restorers: venv\\Scripts\\python download_models.py --extras",
                    )
                with vc2:
                    if v3_restorer == "codeformer":
                        v3_weight = st.slider(
                            "CodeFormer fidelity", 0.0, 1.0, 0.5, 0.05,
                            help="Lower = sharper/stronger restoration; higher = more faithful to the swap. 0.5 is balanced.",
                        )
                    else:
                        v3_weight = 0.5   # only CodeFormer has a fidelity input
                        st.caption("Measured on 4 people (eval_reface.py): GPEN 512 keeps the identity and adds "
                                   "the most detail; GPEN 1024 is marginally better and 4x slower; CodeFormer "
                                   "loses the most identity.")
                with vc3:
                    v3_use_parser = st.checkbox(
                        "Parser blending", value=True,
                        help="Clean hairline/jaw via the face-parsing region mask.",
                    )
                    v3_use_occluder = st.checkbox(
                        "Occlusion handling", value=True,
                        help="Preserve hands / objects / glasses in front of the face.",
                    )
                from face_swappers import available_swappers as _available_swappers
                from reface_engine_v3 import resolve_swapper_name as _resolve_swapper
                _swappers = _available_swappers()
                v3_swapper = st.selectbox(
                    "Swapper",
                    ["auto"] + _swappers,
                    format_func=lambda n: f"auto - best measured ({_resolve_swapper('auto')})" if n == "auto" else n,
                    help="HyperSwap works at 256 px (4x the pixels of inswapper_128) and reads the same "
                         "identity. 'auto' uses whichever eval_reface.py measured best on this PC. "
                         "Missing ones: venv\\Scripts\\python download_models.py --extras",
                )
                from reface_engine_v3 import DEFAULT_IDENTITY_BOOST as _DEFAULT_BOOST
                v3_identity_boost = st.slider(
                    "Identity strength", 0.0, 1.0, float(_DEFAULT_BOOST), 0.05,
                    help="Pushes the identity away from the target's own face before swapping, so less of the "
                         "original person leaks through. 0 = off, 1 = FaceFusion's maximum. Too high can look "
                         "exaggerated.",
                )
                st.caption("V3 runs entirely on GPU via onnxruntime. First run loads the restorer/parser/occluder models.")
                from dfl_bridge import dfm_for as _dfm_for
                _sel_fs = (st.session_state.get('v2_selected_faceset')
                           if st.session_state.get('v2_data_source_mode') == 'faceset' else None)
                _dfm_path = _dfm_for(_sel_fs) if _sel_fs else None
                v3_use_dfm = False
                if _dfm_path:
                    v3_use_dfm = st.checkbox(
                        f"🧠 Use the trained video model for {_sel_fs}", value=True, key="v2_use_dfm",
                        help="DeepFaceLab model trained on this person (🧠 Video Model tab). It learned the face "
                             "itself, not just an identity vector - the best quality for video. "
                             "Untick to use the swapper above.")

                with st.expander("🎬 Realism", expanded=True):
                    v3_preset = st.selectbox(
                        "Preset",
                        ["natural", "maximum_detail", "clean"],
                        index=0,
                        format_func=lambda x: {
                            "natural": "Natural (recommended)",
                            "maximum_detail": "Maximum detail (stills / close-ups)",
                            "clean": "Clean — legacy V3 (for A/B comparison)",
                        }[x],
                        help="Natural matches the frame's lighting, focus and grain, and keeps "
                             "the target's real teeth. Clean reproduces the old behaviour so you "
                             "can compare.",
                    )
                    v3_realism_overrides = {}
                    if st.checkbox("Fine-tune realism", value=False):
                        rc1, rc2 = st.columns(2)
                        with rc1:
                            v3_realism_overrides["detail_transfer"] = st.slider(
                                "Skin detail transfer", 0.0, 1.0, 0.4, 0.05,
                                help="Borrows real pores from the original frame. Scales "
                                     "automatically with how large the face is.",
                            )
                            v3_realism_overrides["grain_match"] = st.slider(
                                "Grain match", 0.0, 1.0, 1.0, 0.05,
                                help="Adds noise matched to the surrounding frame.",
                            )
                        with rc2:
                            v3_realism_overrides["relight"] = st.slider(
                                "Relight strength", 0.0, 1.0, 1.0, 0.05,
                                help="Matches the scene's light direction and white balance.",
                            )
                            v3_realism_overrides["preserve_mouth_interior"] = st.checkbox(
                                "Keep the target's real teeth", value=True,
                                help="Swaps the lips but not the inner mouth. Stops open "
                                     "mouths turning to mush.",
                            )
                            v3_realism_overrides["focus_match"] = st.checkbox(
                                "Focus match", value=True,
                                help="Softens the face to match a soft or blurred frame.",
                            )
            else:
                v3_restorer, v3_weight, v3_use_parser, v3_use_occluder = "codeformer", 0.7, True, True
                v3_preset, v3_realism_overrides = "natural", {}
                v3_swapper = "auto"
                v3_use_dfm, _dfm_path = False, None
                v3_identity_boost = 0.0

            is_video_target = st.session_state.get('v2_is_video', False)
            if use_v3:
                # None of the Legacy V2 controls reach V3 (it has its own above), so
                # they are hidden; these values only fill the shared job params.
                quality_preset, enhancement_mode, enhancer_type = "standard", "auto", "none"
                use_angle_match, enable_occlusion, temporal_smooth = True, True, True
                enhancement_strength, upscale_factor, smoothing_window = 0.7, 1, 3
                protect_glasses, protect_hair = True, True
            else:
                col1, col2, col3 = st.columns(3)
            
                # The preset seeds every control below it. Keeping the values in one
                # place is what stops the dropdown from drifting back into a label
                # that changes two checkboxes and nothing else.
                _PRESET_DEFAULTS = {
                    "fast":         {"enhancer_index": 0, "upscale_index": 0, "smoothing_window": 3,
                                     "occlusion": False, "temporal": False, "strength": 0.7},
                    "standard":     {"enhancer_index": 1, "upscale_index": 1, "smoothing_window": 3,
                                     "occlusion": True,  "temporal": True,  "strength": 0.7},
                    "professional": {"enhancer_index": 2, "upscale_index": 1, "smoothing_window": 5,
                                     "occlusion": True,  "temporal": True,  "strength": 0.8},
                }

                with col1:
                    quality_preset = st.selectbox(
                        "Quality Preset",
                        ["fast", "standard", "professional"],
                        index=1,
                        format_func=lambda x: f"{x.title()} {'⚡' if x=='fast' else '🔧' if x=='standard' else '🌟'}",
                        help="Seeds every option below. Change the preset first, then adjust "
                             "individual controls — they keep whatever you set."
                    )

                with col2:
                    if is_video_target:
                        enhancement_mode = st.selectbox(
                            "Video Enhancement Mode",
                            ["auto", "always", "off"],
                            index=0,
                            format_func=lambda x: {
                                "auto": "Auto (Quality Gate)",
                                "always": "Always (Force)",
                                "off": "Off (None)"
                            }[x],
                            help="Auto enhances only sharp faces in 540p+ videos to avoid inventing clashing detail on low-res sources."
                        )
                        enhancer_type = "gfpgan" if enhancement_mode != "off" else "none"
                    else:
                        enhancement_mode = "auto"
                        enhancer_type = st.selectbox(
                            "Face Enhancer",
                            ["none", "opencv", "gfpgan"],
                            index=_PRESET_DEFAULTS[quality_preset]["enhancer_index"],
                            format_func=lambda x: {"none": "None (Raw)", "opencv": "OpenCV (Basic)", "gfpgan": "GFPGAN (Neural)"}[x]
                        )
            
                with col3:
                    use_angle_match = st.checkbox("🔄 Angle Matching", value=True, help="Match source face angle to target")
            
                col1, col2, col3 = st.columns(3)
            
                with col1:
                    enable_occlusion = st.checkbox("🎭 Occlusion Protection",
                                                  value=_PRESET_DEFAULTS[quality_preset]["occlusion"],
                                                  help="Protect glasses, hands, hair from being overwritten")
            
                with col2:
                    temporal_smooth = st.checkbox("🎬 Temporal Smoothing",
                                                 value=_PRESET_DEFAULTS[quality_preset]["temporal"],
                                                 help="Reduce video jitter (videos only)")
            
                with col3:
                    enhancement_strength = st.slider("Enhancement Strength", 0.0, 1.0,
                                                    _PRESET_DEFAULTS[quality_preset]["strength"], 0.1,
                                                    help="How strongly to apply face enhancement")
            
                # Advanced options
                with st.expander("🔧 Advanced Engineering Options"):
                    col1, col2 = st.columns(2)
                    with col1:
                        if is_video_target:
                            st.caption("ℹ️ Upscale Factor applies to still images only. Video frames stay at source resolution.")
                            upscale_factor = 1
                        else:
                            upscale_factor = st.selectbox(
                                "Upscale Factor", [1, 2, 4],
                                index=_PRESET_DEFAULTS[quality_preset]["upscale_index"]
                            )
                        protect_glasses = st.checkbox("Protect Glasses", value=True)
                    with col2:
                        smoothing_window = st.slider(
                            "Smoothing Window (frames)", 1, 7,
                            _PRESET_DEFAULTS[quality_preset]["smoothing_window"]
                        )
                        protect_hair = st.checkbox("Protect Hair Region", value=True)

            # Video specific time clipping options (both engines)
            if is_video_target:
                with st.expander("🎬 Video Clipping"):
                    tcol1, tcol2 = st.columns(2)
                    with tcol1:
                        start_time_sec = st.number_input("Start Time (seconds)", min_value=0.0, value=0.0, step=1.0)
                    with tcol2:
                        end_time_sec = st.number_input("End Time (seconds)", min_value=0.0, value=0.0, step=1.0,
                                                       help="0.0 means go to the end of the video")
        
        st.markdown("---")
        run_in_background = st.checkbox("🔄 Run in Background", value=False, help="Process in the background. Good for long videos.")
        if _v2_gpu_job and not run_in_background:
            st.caption(f"⏳ `{_v2_gpu_job.job_type}` job `{_v2_gpu_job.id}` is using the GPU — tick "
                      "'Run in Background' to queue behind it, or wait.")
        st.markdown("---")

        # Execute
        has_source = (st.session_state.get('v2_data_source_mode') == 'faceset' and st.session_state.get('v2_selected_faceset')) or \
                     (st.session_state.get('v2_data_source_mode') == 'upload' and st.session_state.get('v2_source_paths'))

        if has_source and st.session_state.get('v2_target_path'):
            if st.button("🚀 Process with V2 Engine", type="primary", use_container_width=True,
                        disabled=bool(_v2_gpu_job) and not run_in_background):
                with st.spinner("Processing with Reface V2..."):
                    try:
                        # Build configuration
                        enhancement_config = EnhancementConfig(
                            enhancer_type=enhancer_type,
                            strength=enhancement_strength,
                            upscale_factor=upscale_factor
                        )
                        
                        occlusion_config = OcclusionConfig(
                            enabled=enable_occlusion,
                            protect_glasses=protect_glasses,
                            protect_hair=protect_hair
                        )
                        
                        video_config = VideoConfig(
                            temporal_smoothing=temporal_smooth,
                            smoothing_window=smoothing_window
                        )
                        
                        target_path = st.session_state['v2_target_path']
                        is_video = st.session_state.get('v2_is_video', False)
                        selected_indices = st.session_state.get('v2_selected_target_faces', [])
                        target_face_indices = selected_indices if len(selected_indices) > 0 else None
                        # Every detected face's embedding (not just the ticked ones): V3 assigns
                        # each face it meets to the nearest of these, so a bystander matches
                        # their own reference instead of borrowing a selected one.
                        _ref_embs = [f.get('embedding') for f in st.session_state.get('v2_detected_faces', [])]
                        target_face_embeddings = (_ref_embs if target_face_indices and _ref_embs
                                                  and all(e is not None for e in _ref_embs) else None)

                        if run_in_background:
                            from job_manager import add_job_to_queue
                            
                            params = {
                                'target_path': target_path,
                                'is_video': is_video,
                                'target_face_indices': target_face_indices,
                                'use_angle_matching': use_angle_match, # Added this parameter
                                'enhancement_mode': enhancement_mode,
                                'enhancement_config': enhancement_config.__dict__,
                                'occlusion_config': occlusion_config.__dict__,
                                'video_config': video_config.__dict__
                            }
                            
                            # Add time parameters if video
                            if is_video:
                                params['start_time'] = start_time_sec
                                params['end_time'] = end_time_sec if end_time_sec > 0.0 else None
                            
                            if st.session_state.get('v2_data_source_mode') == 'faceset':
                                params['faceset_name'] = st.session_state['v2_selected_faceset']
                            else:
                                params['source_paths'] = st.session_state['v2_source_paths']
                            
                            if use_v3:
                                params['target_face_embeddings'] = target_face_embeddings
                                params['swapper'] = v3_swapper
                                params['identity_boost'] = v3_identity_boost
                                if v3_use_dfm and _dfm_path:
                                    params['dfm_path'] = str(_dfm_path)
                                params['restorer'] = v3_restorer
                                params['restorer_weight'] = v3_weight
                                params['use_parser'] = v3_use_parser
                                params['use_occluder'] = v3_use_occluder
                                params['realism_preset'] = v3_preset
                                params['realism_overrides'] = v3_realism_overrides
                                job_type = "reface_video_v3" if is_video else "reface_image_v3"
                                if v3_use_dfm and _dfm_path:
                                    job_type = "reface_video_dfm" if is_video else "reface_image_dfm"
                            else:
                                job_type = "reface_video_v2" if is_video else "reface_image_v2"
                            job = add_job_to_queue(job_type, params)
                            
                            st.success(f"✅ Job {job.id} added to background queue!")
                            st.info("Check the '⚙️ Background Jobs' tab to see progress.")
                        else:
                            # Create engine
                            if use_v3:
                                engine = RefaceEngineV3(
                                    dfm_path=str(_dfm_path) if (v3_use_dfm and _dfm_path) else None,
                                    swapper=v3_swapper,
                                    identity_boost=v3_identity_boost,
                                    restorer=v3_restorer,
                                    restorer_weight=v3_weight,
                                    use_parser=v3_use_parser,
                                    use_occluder=v3_use_occluder,
                                    realism_preset=v3_preset,
                                    realism_overrides=v3_realism_overrides,
                                )
                            else:
                                engine = RefaceEngineV2(
                                    enhancement_config=enhancement_config,
                                    occlusion_config=occlusion_config,
                                    video_config=video_config
                                )
                            
                            # Get or build faceset
                            if st.session_state.get('v2_data_source_mode') == 'faceset':
                                faceset = engine.load_faceset_by_name(st.session_state['v2_selected_faceset'])
                                if not faceset:
                                    st.error("Failed to load faceset")
                                    st.stop()
                            else:
                                st.text("Building faceset from source media...")
                                progress = st.progress(0)
                                status_build = st.empty()
                                eta_v2_build = ETACalculator(len(st.session_state['v2_source_paths']))
                                def update_progress(current, total):
                                    eta_str = eta_v2_build.get_eta_string(current)
                                    progress_pct = int((current / total) * 100) if total > 0 else 0
                                    progress.progress(current / total)
                                    status_build.text(f"Building faceset: {current}/{total} ({progress_pct}%) ({eta_str} remaining)...")
                                
                                if use_v3:
                                    from identity_builder import faceset_from_media
                                    faceset = faceset_from_media(st.session_state['v2_source_paths'],
                                                                 engine.app, name="v2_temp")
                                    update_progress(1, 1)
                                else:
                                    faceset = engine.build_faceset_from_media(
                                        st.session_state['v2_source_paths'],
                                        faceset_name="v2_temp",
                                        progress_callback=update_progress
                                    )
                            
                            if not faceset or not faceset.faces:
                                st.error("No faces found in source!")
                                st.stop()
                            
                            st.success(f"✅ Faceset ready with {len(faceset.faces)} faces")
                            
                            # Perform swap
                            
                            st.text("Swapping faces with V2 engine...")
                            swap_progress = st.progress(0)
                            
                            status_v2_swap = st.empty()
                            def update_swap(current, total):
                                if 'eta_v2_swap' not in st.session_state or st.session_state.eta_v2_swap_total != total:
                                    st.session_state.eta_v2_swap = ETACalculator(total)
                                    st.session_state.eta_v2_swap_total = total
                                    
                                eta_str = st.session_state.eta_v2_swap.get_eta_string(current)
                                # st.progress rejects anything outside [0, 1], and an
                                # engine working from an unknown frame count can report
                                # a ratio above 1. Clamp rather than crash the page.
                                ratio = min(1.0, max(0.0, current / total)) if total > 0 else 0.0
                                progress_pct = int(ratio * 100)
                                swap_progress.progress(ratio)
                                status_v2_swap.text(f"Swapping frames: {current}/{total} ({progress_pct}%) ({eta_str} remaining)...")
                            
                            if is_video:
                                # Apply chosen end time
                                final_end_time = end_time_sec if end_time_sec > 0.0 else None

                                if use_v3:
                                    result = engine.reface_video_v3(
                                        target_video_path=target_path,
                                        faceset=faceset,
                                        target_face_indices=target_face_indices,
                                        target_face_embeddings=target_face_embeddings,
                                        progress_callback=update_swap,
                                        start_time=start_time_sec,
                                        end_time=final_end_time,
                                    )
                                else:
                                    result = engine.reface_video_with_faceset_v2(
                                        target_video_path=target_path,
                                        faceset=faceset,
                                        target_face_indices=target_face_indices,
                                        use_angle_matching=use_angle_match,
                                        apply_occlusion=enable_occlusion,
                                        enhancement_mode=enhancement_mode,
                                        progress_callback=update_swap,
                                        start_time=start_time_sec,
                                        end_time=final_end_time
                                    )
                            else:
                                if use_v3:
                                    result = engine.reface_image_v3(
                                        target_image_path=target_path,
                                        faceset=faceset,
                                        target_face_indices=target_face_indices,
                                        target_face_embeddings=target_face_embeddings,
                                    )
                                else:
                                    result = engine.reface_with_faceset_v2(
                                        target_image_path=target_path,
                                        faceset=faceset,
                                        target_face_indices=target_face_indices,
                                        use_angle_matching=use_angle_match,
                                        apply_occlusion=enable_occlusion
                                    )
                                swap_progress.progress(1.0)
                            
                            if result.success:
                                st.success(f"✅ {result.message}")
                                
                                # Display result
                                if is_video and result.output_path:
                                    st.video(result.output_path)
                                elif result.output_path:
                                    st.image(result.output_path, caption="V2 Result")
                                
                                # Download button
                                if result.output_path and os.path.exists(result.output_path):
                                    with open(result.output_path, "rb") as f:
                                        suffix = Path(result.output_path).suffix.lower()
                                        mime = "video/mp4" if is_video else (
                                            "image/png" if suffix == ".png" else "image/jpeg"
                                        )
                                        st.download_button(
                                            "📥 Download Result",
                                            data=f.read(),
                                            file_name=Path(result.output_path).name,
                                            mime=mime,
                                        )
                            else:
                                st.error(f"❌ {result.message}")
                        
                    except Exception as e:
                        st.error(f"❌ Error: {str(e)}")
                        import traceback
                        st.code(traceback.format_exc())
        else:
            st.info("👆 Upload source and target media, then click Process to begin")

        with tab_v2_build:
            st.markdown("### 📦 Build & Manage Facesets (V2)")
            st.info("Create named collections of faces (Facesets) from your photos and videos. Using a faceset improves reface quality by providing more angles.")
            
            # --- Documentation Section ---
            with st.expander("📚 How to Build a Professional Faceset", expanded=False):
                st.markdown("""
## Creating a High-Quality 3D Face Dataset

For **professional results**, your faceset should include faces from **multiple angles**. 
This allows the engine to match the source angle to the target pose for seamless swaps.

### 🎯 Required Angles (7-Point System)

| Priority | Angle | Yaw Range | How to Capture |
|----------|-------|-----------|----------------|
| 🔴 **Critical** | Front | -15° to +15° | Look directly at camera |
| 🟡 **Important** | Left 45° | -60° to -30° | Turn head slightly left |
| 🟡 **Important** | Right 45° | +30° to +60° | Turn head slightly right |
| 🟡 **Important** | Up | pitch > 15° | Tilt chin up slightly |
| 🟢 **Optional** | Left 90° | < -60° | Full profile shot (left side) |
| 🟢 **Optional** | Right 90° | > +60° | Full profile shot (right side) |
| 🟢 **Optional** | Down | pitch < -15° | Tilt chin down |

### 💡 Pro Tips

1. **Best Source Method**: Upload a **video of the person slowly turning their head** from left to right. 
   This captures all angles automatically in one go!

2. **Lighting**: Ensure even, soft lighting across all photos. Harsh shadows create artifacts.

3. **Resolution**: Higher resolution source = better quality swaps. Aim for at least 512px face size.

4. **Expressions**: Include:
   - Neutral expression (primary)
   - Slight smile
   - Eyes open naturally

5. **Quantity**: Target **50-200 faces** for optimal angle coverage.

### ⚠️ Common Mistakes to Avoid

| ❌ Problem | ✅ Solution |
|-----------|------------|
| Only frontal photos | Add profile and angled shots |
| Harsh lighting/shadows | Use soft, even lighting |
| Low resolution | Use higher quality source images |
| Blurry images | Ensure sharp focus on face |
| Only one expression | Include neutral + smile |

### 📊 Quality Scoring

After building a faceset, you'll see:
- **Quality Score (0-100)**: Higher = better angle coverage
- **Grade (A+ to F)**: Quick assessment
- **Coverage Grid**: Shows which angles are captured
- **Suggestions**: What to add for improvement
                """)
            
            # --- Create New Faceset ---
            with st.expander("✨ Create New Faceset", expanded=True):

                col1, col2 = st.columns([1, 2])
                with col1:
                    new_faceset_name = st.text_input("Faceset Name", placeholder="e.g. MyFriend_John", key="v2_new_fs_name")
                with col2:
                    faceset_files = st.file_uploader("Upload Source Media", accept_multiple_files=True, type=['jpg', 'png', 'mp4', 'mov'], key="v2_new_fs_files")
                
                if st.button("🔨 Build & Save Faceset", disabled=not (new_faceset_name and faceset_files), key="v2_build_fs_btn"):
                    if not new_faceset_name.strip():
                        st.error("Please provide a valid name.")
                    else:
                        # Save to PERMANENT faceset-specific directory
                        faceset_media_dir = Path(__file__).parent / "facesets" / new_faceset_name / "source_media"
                        faceset_media_dir.mkdir(parents=True, exist_ok=True)
                        
                        saved_paths = []
                        for uploaded_file in faceset_files:
                            path = faceset_media_dir / uploaded_file.name
                            with open(path, "wb") as f:
                                f.write(uploaded_file.getbuffer())
                            saved_paths.append(str(path))
                        
                        progress_bar = st.progress(0)
                        status_text = st.empty()
                        
                        eta_build = ETACalculator(len(saved_paths))
                        def update_progress(current, total):
                            eta_str = eta_build.get_eta_string(current)
                            progress_pct = int((current / total) * 100) if total > 0 else 0
                            progress_bar.progress(current / total)
                            status_text.text(f"Processing media {current}/{total} ({progress_pct}%) ({eta_str} remaining)...")
                            
                        try:
                            # Identity builder: finds the person in every photo/frame (not just the
                            # detector's first face), drops small/blurry/duplicate/outlier faces and
                            # spreads video frames across head poses. See identity_builder.py.
                            from identity_builder import build_identity, save_identity
                            identity, id_report = build_identity(
                                new_faceset_name.strip(), saved_paths, get_face_analyzer(),
                                progress=lambda i, n, _name: update_progress(i, n))
                            if identity is None:
                                raise ValueError(id_report.get("reason", "Could not build an identity."))
                            save_identity(identity)
                            faceset = Faceset.load(Path(__file__).parent / "facesets" / f"{identity.slug}.pkl")

                            st.success(f"✅ Identity '{identity.slug}' built from {id_report['kept']} of "
                                       f"{id_report['faces_seen']} detected faces — grade {id_report['grade']}, "
                                       f"consistency {id_report['consistency']:.2f}")
                            _dropped = id_report.get("dropped") or {}
                            if _dropped:
                                st.caption("Left out: " + ", ".join(f"{n} × {why}" for why, n in _dropped.items()))
                            _weak = id_report.get("weakest") or []
                            if _weak:
                                with st.expander("Weakest photos kept (check these are really the person)"):
                                    for w in _weak:
                                        _where = Path(w["source"]).name + (f" @ frame {w['frame']}" if w.get("frame") is not None else "")
                                        st.caption(f"{_where}: similarity {w['similarity']:.2f}")
                            
                            # Show detailed coverage analysis
                            st.markdown("#### 📊 Faceset Quality Analysis")
                            
                            # Quality score and grade
                            quality_score = faceset.get_quality_score()
                            quality_grade = faceset.get_quality_grade()
                            
                            score_col1, score_col2 = st.columns(2)
                            with score_col1:
                                st.metric("Quality Score", f"{quality_score:.0f}/100")
                            with score_col2:
                                grade_emoji = {"A+": "🏆", "A": "⭐", "B": "👍", "C": "👌", "D": "⚠️", "F": "❌"}.get(quality_grade, "")
                                st.metric("Grade", f"{grade_emoji} {quality_grade}")
                            
                            # Detailed angle coverage
                            detailed_cov = faceset.get_detailed_coverage()
                            
                            st.markdown("**Angle Coverage:**")
                            angle_cols = st.columns(7)
                            angle_order = ['front', 'left_45', 'right_45', 'up', 'down', 'left_90', 'right_90']
                            angle_labels = {
                                'front': '🎯 Front', 'left_45': '↖️ Left 45°', 'right_45': '↗️ Right 45°',
                                'up': '⬆️ Up', 'down': '⬇️ Down', 'left_90': '⬅️ Left 90°', 'right_90': '➡️ Right 90°'
                            }
                            
                            for i, angle in enumerate(angle_order):
                                data = detailed_cov[angle]
                                with angle_cols[i]:
                                    count = data['count']
                                    priority = data['priority']
                                    color = "green" if count > 0 else ("red" if data['required'] else "gray")
                                    emoji = "✅" if count > 0 else ("❌" if data['required'] else "⬜")
                                    st.markdown(f"**{emoji}**")
                                    st.caption(f"{angle_labels.get(angle, angle)}")
                                    st.caption(f"{count} faces")
                            
                            # Suggestions
                            suggestions = faceset.get_suggestions()
                            if suggestions:
                                st.markdown("**💡 Suggestions:**")
                                for suggestion in suggestions:
                                    st.markdown(f"- {suggestion}")
                            
                        except Exception as e:
                            import traceback
                            st.error(f"Failed to build faceset: {e}")
                            st.code(traceback.format_exc())

            
            st.markdown("---")
            
            # --- Manage Existing Facesets ---
            st.subheader("📚 Your Facesets")
            
            # Listing files needs no models. (This used to keep a whole RefaceEngineV2 -
            # ~2.5 GB of VRAM - alive in the Streamlit process for the session.)
            from types import SimpleNamespace
            _fs_dir = Path(__file__).parent / "facesets"
            engine = SimpleNamespace(
                faceset_dir=_fs_dir,
                load_faceset_by_name=lambda n: Faceset.load(_fs_dir / f"{n}.pkl") if (_fs_dir / f"{n}.pkl").exists() else None,
            )
            facesets = sorted(f.stem for f in _fs_dir.glob("*.pkl")) if _fs_dir.exists() else []
            
            if not facesets:
                st.info("No saved facesets found.")
            else:
                for fs_name in facesets:
                    with st.container():
                        # Load faceset ONCE at start of container
                        loaded_fs = None
                        face_count = 0
                        preview_img = None
                        
                        try:
                            loaded_fs = engine.load_faceset_by_name(fs_name)
                            if loaded_fs and loaded_fs.faces:
                                face_count = len(loaded_fs.faces)
                                # Get first face's image and crop
                                first_face = loaded_fs.faces[0]
                                import cv2
                                img = cv2.imread(first_face.image_path)
                                if img is not None:
                                    bbox = first_face.bbox
                                    x1, y1, x2, y2 = [int(b) for b in bbox]
                                    pad = 20
                                    h, w = img.shape[:2]
                                    x1, y1 = max(0, x1-pad), max(0, y1-pad)
                                    x2, y2 = min(w, x2+pad), min(h, y2+pad)
                                    crop = img[y1:y2, x1:x2]
                                    preview_img = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
                        except:
                            pass
                        
                        c1, c2, c3 = st.columns([1, 3, 1])
                        
                        with c1:
                            if preview_img is not None:
                                st.image(preview_img, width=80)
                            else:
                                st.markdown("🖼️")
                        
                        with c2:
                            st.markdown(f"**{fs_name}**")
                            if face_count > 0:
                                st.caption(f"{face_count} faces")
                        
                        with c3:
                            if st.button("🗑️", key=f"v2_del_fs_{fs_name}"):
                                try:
                                    # Delete pkl file
                                    (engine.faceset_dir / f"{fs_name}.pkl").unlink()
                                    # Delete source media folder if exists
                                    import shutil
                                    media_dir = engine.faceset_dir / fs_name
                                    if media_dir.exists():
                                        shutil.rmtree(media_dir)
                                    identity_dir = Path(__file__).parent / "identities" / fs_name
                                    if identity_dir.exists():
                                        shutil.rmtree(identity_dir)
                                    st.success(f"Deleted {fs_name}")
                                    st.rerun()
                                except Exception as e:
                                    st.error(str(e))

        with tab_v2_dfl:
            st.markdown("### 🧠 Trained video model (DeepFaceLab)")
            st.caption("The best quality for video. Instead of a 512-number identity vector, DeepFaceLab trains a "
                       "network on thousands of frames of one person, so it learns the face itself - skin, teeth, "
                       "expressions. It takes days of GPU time, runs in the background, and can be stopped and "
                       "resumed any time; every stop saves the model and exports it so you can already use it.")
            import dfl_bridge
            from identity_builder import list_identities, load_manifest
            _dfl_problem = dfl_bridge.available()
            _idents = list_identities()
            if _dfl_problem:
                st.error(f"DeepFaceLab isn't usable: {_dfl_problem}")
            elif not _idents:
                st.info("Build an identity first in 📦 Build Faceset - it decides which face in every frame is the person.")
            else:
                dfl_slug = st.selectbox("Person (identity)", _idents, key="dfl_identity")
                _man = load_manifest(dfl_slug) or {"faces": []}
                _srcs = sorted({f["source"] for f in _man["faces"] if Path(f["source"]).exists()})
                _vids = [x for x in _srcs if Path(x).suffix.lower() in dfl_bridge.VIDEO_EXTS]
                _pics = [x for x in _srcs if Path(x).suffix.lower() in dfl_bridge.IMAGE_EXTS]
                _extra_dir = st.text_input("More videos of the person - a folder on this PC (optional)",
                                           key=f"dfl_extra_{dfl_slug}")
                _extra = []
                if _extra_dir and Path(_extra_dir).is_dir():
                    _extra = sorted(str(x) for x in Path(_extra_dir).iterdir()
                                    if x.suffix.lower() in dfl_bridge.VIDEO_EXTS | dfl_bridge.IMAGE_EXTS)
                elif _extra_dir:
                    st.warning("That folder doesn't exist.")
                st.caption(f"{len(_vids)} video(s) and {len(_pics)} photo(s) from the identity, plus {len(_extra)} "
                           "from the folder. Aim for several minutes of video of the person: turning the head, "
                           "talking, different light. Photos alone are rarely enough.")
                _phase_labels = {
                    "base": "1 · Base - learn the face (until the loss stops falling, ~150-300k iterations)",
                    "sharpen": "2 · Sharpen - random warp off, LR dropout on (~50-100k)",
                    "detail": "3 · Detail - light GAN for pores and teeth (~20-50k)",
                }
                dfl_phase = st.radio("Phase", list(_phase_labels), format_func=_phase_labels.get,
                                     key=f"dfl_phase_{dfl_slug}")

                _dfl_jobs = [j for j in _v2_jobs.list_jobs(limit=200)
                             if j.job_type == "train_dfl" and (j.params or {}).get("slug") == dfl_slug]
                _dfl_active = next((j for j in _dfl_jobs
                                    if j.status in (_V2JS.PENDING, _V2JS.QUEUED, _V2JS.RUNNING)), None)
                _dfl_paused = next((j for j in _dfl_jobs if j.status == _V2JS.PAUSED), None)
                _dfl_other_gpu = (_v2_gpu_job if (_v2_gpu_job and (not _dfl_active or _v2_gpu_job.id != _dfl_active.id))
                                  else None)

                bc1, bc2 = st.columns(2)
                if _dfl_active:
                    if bc1.button("⏹ Stop (saves and exports the model)", key="dfl_stop", use_container_width=True):
                        _v2_jobs.request_stop(_dfl_active.id)
                        st.toast("Stopping - DeepFaceLab saves first, this can take a minute.")
                elif _dfl_paused:
                    if bc1.button("▶ Resume training", key="dfl_resume", type="primary", use_container_width=True):
                        _dfl_paused.params = {**(_dfl_paused.params or {}), "phase": dfl_phase}
                        _v2_jobs.save_job(_dfl_paused)
                        _v2_jobs.resume_job(_dfl_paused.id)
                        from job_manager import start_queue_worker as _sqw
                        _sqw(str(Path(__file__).parent / "jobs"))
                        st.rerun()
                else:
                    _media = _vids + _pics + _extra
                    # Paused 2026-10-14: extract + masks verified, training not yet
                    # (dfl_runner's answer patch must survive DeepFaceLab's spawned workers).
                    st.warning("Not finished yet - training is disabled until it has been verified end to end.")
                    if bc1.button("🚀 Start training", key="dfl_start", type="primary", use_container_width=True,
                                  disabled=True):
                        from job_manager import add_job_to_queue as _dfl_add
                        _dfl_add("train_dfl", {"slug": dfl_slug, "media": _media, "phase": dfl_phase},
                                 jobs_dir=str(Path(__file__).parent / "jobs"))
                        st.rerun()
                if _dfl_other_gpu:
                    st.caption(f"Queued behind `{_dfl_other_gpu.job_type}` job `{_dfl_other_gpu.id}`.")

                _dfl_polling = bool(_dfl_active) and _v2_jobs.is_worker_running()

                @st.fragment(run_every=5 if _dfl_polling else None)
                def _dfl_status():
                    jobs_now = [j for j in _v2_jobs.list_jobs(limit=200)
                                if j.job_type == "train_dfl" and (j.params or {}).get("slug") == dfl_slug]
                    j = jobs_now[0] if jobs_now else None
                    if j is not None:
                        d = j.details or {}
                        st.markdown(f"**{j.message}**")
                        cols = st.columns(4)
                        cols[0].metric("Iteration", f"{d.get('iter', 0):,}")
                        loss = d.get("loss") or []
                        cols[1].metric("Loss (src)", f"{loss[0]:.4f}" if loss else "-")
                        cols[2].metric("ms / iteration", d.get("ms_per_iter") or "-")
                        cols[3].metric("Training faces", d.get("aligned") or "-")
                        if d.get("clean"):
                            st.caption("Training set: " + ", ".join(f"{k} {v}" for k, v in d["clean"].items()))
                    if dfl_bridge.dfm_for(dfl_slug):
                        st.success(f"✅ Trained model ready for {dfl_slug}. In 🔄 Quick Swap pick this identity "
                                   "under 📦 Use Faceset and keep '🧠 Use the trained video model' ticked.")
                    if _dfl_polling and not (j and j.status in (_V2JS.PENDING, _V2JS.QUEUED, _V2JS.RUNNING)):
                        st.rerun()

                _dfl_status()
                with st.expander("Log"):
                    _log = dfl_bridge.Workspace(dfl_slug).log
                    st.code(_log.read_text(encoding="utf-8", errors="replace")[-4000:]
                            if _log.exists() else "(no log yet)")

        with tab_v2_history:
            st.markdown("### 📜 Reface History (V2)")
            
            output_dir = Path(__file__).parent / "reface_output"
            output_dir.mkdir(exist_ok=True)
            
            # Refresh button
            if st.button("🔄 Refresh List", key="v2_refresh_history"):
                st.rerun()
            
            # List files filtered by V2 prefix
            all_files = list(output_dir.glob("*.jpg")) + list(output_dir.glob("*.jpeg")) + \
                        list(output_dir.glob("*.png")) + list(output_dir.glob("*.mp4")) + \
                        list(output_dir.glob("*.avi"))
            files = sorted([f for f in all_files if f.name.startswith("refaced_v2")], key=os.path.getmtime, reverse=True)
            
            if not files:
                st.info("No reface results found yet.")
            else:
                st.caption(f"Found {len(files)} result(s)")
                
                # Grid view
                cols = st.columns(3)
                for i, file_path in enumerate(files):
                    with cols[i % 3]:
                        st.markdown("---")
                        
                        is_video = file_path.suffix.lower() in ['.mp4', '.avi', '.mov', '.mkv']
                        
                        try:
                            if is_video:
                                # Try to show MP4 video
                                if file_path.suffix.lower() == '.mp4':
                                    st.video(str(file_path))
                                else:
                                    # For AVI/others: Generate and show thumbnail
                                    import cv2
                                    cap = cv2.VideoCapture(str(file_path))
                                    ret, frame = cap.read()
                                    cap.release()
                                    
                                    if ret:
                                        # Convert BGR to RGB
                                        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                                        st.image(frame, caption=f"Preview ({file_path.suffix})", use_container_width=True)
                                    else:
                                        st.warning(f"No preview for {file_path.suffix}")
                                    
                                    # Add "Convert to MP4" button
                                    if st.button("🔄 Convert to Playable MP4", key=f"v2_conv_{file_path.name}"):
                                        with st.spinner("Converting..."):
                                            try:
                                                import subprocess
                                                
                                                from ffmpeg_utils import _ffmpeg_exe
                                                # Locate FFmpeg
                                                ffmpeg_exe = _ffmpeg_exe()
                                                
                                                mp4_path = file_path.with_suffix('.mp4')
                                                subprocess.run([
                                                    ffmpeg_exe, '-y', '-i', str(file_path),
                                                    '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
                                                    '-pix_fmt', 'yuv420p', str(mp4_path)
                                                ], check=True)
                                                file_path.unlink() # Remove old avi
                                                st.success("Converted! Refreshing...")
                                                st.rerun()
                                            except Exception as e:
                                                st.error(f"FFmpeg failed: {e}")
                            else:
                                st.image(str(file_path), use_container_width=True)
                        except Exception as e:
                            st.error(f"Error loading preview: {e}")
                        
                        from datetime import datetime
                        st.caption(f"📅 {datetime.fromtimestamp(file_path.stat().st_mtime).strftime('%Y-%m-%d %H:%M')}")
                        st.caption(f"📁 {file_path.name}")
                        
                        # Actions
                        c1, c2 = st.columns(2)
                        with c1:
                            # Two steps so a page with many large videos does not
                            # read every one of them into memory on every rerun.
                            # The "prepared" flag lives in session_state: a plain
                            # nested button would disappear on the rerun that the
                            # download itself triggers.
                            prep_key = f"v2_prep_dl_{file_path.name}"
                            if not st.session_state.get(prep_key):
                                if st.button("⬇️ Download", key=f"v2_btn_dl_{file_path.name}",
                                             help="Prepare download"):
                                    st.session_state[prep_key] = True
                                    st.rerun()
                            else:
                                with open(file_path, "rb") as f:
                                    st.download_button(
                                        "💾 Save",
                                        data=f.read(),
                                        file_name=file_path.name,
                                        mime="video/mp4" if is_video else "image/jpeg",
                                        key=f"v2_dl_{file_path.name}"
                                    )
                        with c2:
                            if st.button("🗑️", key=f"v2_del_{file_path.name}", help="Delete file"):
                                try:
                                    file_path.unlink()
                                    st.success("Deleted!")
                                    st.rerun()
                                except Exception as e:
                                    st.error(f"Delete failed: {e}")

        with tab_v2_jobs:
            st.markdown("### ⚙️ Background Jobs (V2)")
            st.info("V2 Background Jobs run asynchronously. Check terminal for raw logs.")
            
            try:
                from job_manager import JobManager, JobStatus
                job_manager = JobManager()
                
                # Auto-refresh toggle
                col1, col2 = st.columns([3, 1])
                with col2:
                    if st.button("🔄 Refresh", key="v2_jobs_refresh"):
                        st.rerun()
                
                jobs = job_manager.list_jobs(limit=20)
                
                if not jobs:
                    st.info("No jobs found. Start a reface operation to see jobs here!")
                else:
                    # Running jobs first
                    running_jobs = [j for j in jobs if j.status == JobStatus.RUNNING]
                    if running_jobs:
                        st.subheader("🔄 Currently Running")
                        for job in running_jobs:
                            with st.container():
                                col1, col2, col3 = st.columns([4, 1, 1])
                                with col1:
                                    st.markdown(f"**Job {job.id}** - {job.job_type}")
                                    progress_pct = int(job.progress * 100)
                                    st.progress(job.progress, text=f"{progress_pct}% - {job.message}")
                                    st.caption(f"Started: {job.started_at}")
                                with col2:
                                    if st.button("⏹️ Stop", key=f"v2_stop_{job.id}", help="Pause this job"):
                                        job_manager.request_stop(job.id)
                                        st.warning("⏸️ Stop requested - job will pause at next frame")
                                        import time
                                        time.sleep(1)
                                        st.rerun()
                                with col3:
                                    if st.button("🗑️", key=f"v2_del_running_{job.id}", help="Delete this job"):
                                        job_manager.request_stop(job.id)
                                        import time
                                        time.sleep(0.5)
                                        job_manager.delete_job(job.id)
                                        st.success("Job deleted")
                                        st.rerun()
                        st.markdown("---")
                    
                    # Paused jobs
                    paused_jobs = [j for j in jobs if j.status == JobStatus.PAUSED]
                    if paused_jobs:
                        st.subheader("⏸️ Paused Jobs")
                        for job in paused_jobs:
                            with st.container():
                                col1, col2 = st.columns([4, 1])
                                with col1:
                                    st.markdown(f"**Job {job.id}** - {job.job_type}")
                                    progress_pct = int(job.progress * 100)
                                    st.progress(job.progress, text=f"{progress_pct}%")
                                    st.caption(f"Paused at frame {job.last_frame}")
                                with col2:
                                    if st.button("▶️ Resume", key=f"v2_resume_{job.id}"):
                                        job_manager.resume_job(job.id)
                                        from job_manager import start_queue_worker
                                        start_queue_worker(str(job_manager.jobs_dir))
                                        st.success("▶️ Job queued for resume!")
                                        st.rerun()
                        st.markdown("---")
                    
                    # Queued jobs
                    from job_manager import JobStatus as JS
                    queued_jobs = [j for j in jobs if j.status in [JobStatus.PENDING, JS.QUEUED]]
                    if queued_jobs:
                        st.subheader("📋 Queue")
                        for i, job in enumerate(sorted(queued_jobs, key=lambda x: x.created_at)):
                            pos = i + 1
                            st.markdown(f"**#{pos}** Job {job.id} - {job.job_type}")
                        st.caption(f"{len(queued_jobs)} job(s) waiting")
                        st.markdown("---")
                    
                    # Completed/Failed jobs
                    finished_jobs = [j for j in jobs if j.status in [JobStatus.COMPLETED, JobStatus.FAILED]]
                    if finished_jobs:
                        st.subheader("✅ Completed Jobs")
                        for job in finished_jobs[:10]:
                            with st.container():
                                status_icon = "✅" if job.status == JobStatus.COMPLETED else "❌"
                                st.markdown(f"{status_icon} **Job {job.id}** - {job.job_type}")
                                st.caption(job.message)
                                
                                if job.result_path and Path(job.result_path).exists():
                                    col1, col2 = st.columns([3, 1])
                                    with col1:
                                        if job.result_path.endswith(('.mp4', '.avi')):
                                            st.video(job.result_path)
                                        else:
                                            st.image(job.result_path, width=200)
                                    with col2:
                                        with open(job.result_path, "rb") as f:
                                            st.download_button(
                                                "📥 Download",
                                                data=f.read(),
                                                file_name=Path(job.result_path).name,
                                                key=f"v2_dl_job_{job.id}"
                                            )
                                
                                if job.error and job.status == JobStatus.FAILED:
                                    with st.expander("Show Error"):
                                        st.code(job.error)
                                
                                if st.button("🗑️ Remove", key=f"v2_del_job_{job.id}"):
                                    job_manager.delete_job(job.id)
                                    st.rerun()
                                
                                st.markdown("---")
            except Exception as e:
                st.error(f"Error loading jobs: {e}")


elif page == "⚙️ Settings":
    st.title("⚙️ Settings")
    
    st.subheader("Database")
    
    col1, col2 = st.columns(2)
    with col1:
        st.info(f"**Host:** {os.getenv('DB_HOST', 'localhost')}")
        st.info(f"**Database:** {os.getenv('DB_NAME', 'antigravity_local')}")
    
    with col2:
        if st.button("🔄 Reinitialize Database"):
            init_db()
            st.success("Database reinitialized!")
        
        if st.button("🗑️ Clear All Data", type="secondary"):
            if st.checkbox("I understand this will delete all data"):
                # Clear data using JsonDatabase
                db = JsonDatabase()
                db.persons = {}
                db.faces = {}
                db.save_persons()
                db.save_faces()
                st.warning("All data cleared!")
                st.rerun()
    
    st.markdown("---")
    
    st.subheader("Mining Settings")
    st.code(f"""
FRAME_INTERVAL = {os.getenv('FRAME_INTERVAL', '1.0')} seconds
QUALITY_THRESHOLD = {os.getenv('QUALITY_THRESHOLD', '0.6')}
DUPLICATE_THRESHOLD = {os.getenv('DUPLICATE_THRESHOLD', '0.05')}
    """)
    
    st.markdown("---")
    
    st.subheader("Clear Data Sources")
    if st.button("🗑️ Clear All Data Sources"):
        st.session_state.data_sources = []
        save_data_sources([])
        st.success("Data sources cleared!")
        st.rerun()


# Footer
st.markdown("---")
st.markdown(
    "<div style='text-align: center; color: var(--text-muted); font-size: 12px; padding: 12px 0 24px; font-weight: 500;'>"
    "🔬 Your Gallery Studio v1.2 • Biometric Gallery & Creative AI Suite"
    "</div>",
    unsafe_allow_html=True
)
