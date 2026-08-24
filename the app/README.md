# Antigravity Local

**Biometric Gallery & Dataset Curation Tool**

A standalone face mining and gallery management tool with PostgreSQL pgvector for embedding storage and deduplication.

## Features

- 🎥 **Face Mining**: Extract faces from videos using InsightFace (Buffalo_L model)
- 🔍 **Deduplication**: Prevents duplicate faces using pgvector cosine similarity (< 0.05 threshold)
- 👥 **Person Clustering**: Group faces by identity
- 🖼️ **Gallery Dashboard**: Streamlit-based UI for face management
- 📤 **LoRA Export**: Export person facesets with captions for training
- 🎭 **Reface**: Face swap in images and videos
- ✨ **Magic Undress**: AI-powered clothes transformation using Stable Diffusion + ControlNet
- 🚀 **GPU Optimized**: CUDA support for fast processing

## Prerequisites

1. **Python 3.10+** (Python 3.13 for main app, Python 3.10 for AI features)
2. **PostgreSQL** with pgvector extension
3. **NVIDIA GPU** with CUDA Toolkit (required for AI features)

### Installing pgvector

```sql
-- In PostgreSQL (as superuser)
CREATE EXTENSION IF NOT EXISTS vector;
```

## Quick Start

### 1. Setup Main Environment

```cmd
cd D:\AndroidScan\gallary\antigravity-local

# Create virtual environment
python -m venv venv
venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure Database

Copy `.env.template` to `.env` and fill in your PostgreSQL credentials:

```cmd
copy .env.template .env
# Edit .env with your database credentials
```

### 3. Initialize Database

```cmd
python database.py
```

### 4. Run Dashboard

```cmd
run_dashboard.bat
```
Or manually:
```cmd
venv\Scripts\activate.bat
streamlit run dashboard.py
```

Open http://localhost:8501 in your browser.

---

## Magic Undress Feature (Optional AI Setup)

Clothes restyle via Stable Diffusion inpaint + ControlNet OpenPose. Requires **Python 3.10** and a separate virtual environment.

### Setup venv_ai

```cmd
cd "D:\AndroidScan\gallary\the app"

py -3.10 -m venv venv_ai
venv_ai\Scripts\activate.bat

pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements_ai.txt
```

> **Note**: The first job downloads several GB of models into the Hugging Face cache. Jobs run on the same background queue as Reface (`undress_image`); results land in `outputs/undress/`.

Optional: `python download_models.py selfie_segmenter` so person masks use MediaPipe Tasks instead of the legacy API.

---

## Project Structure

```
antigravity-local/
├── .env.template      # Environment config template
├── requirements.txt   # Python dependencies (main app)
├── database.py        # SQLAlchemy models + pgvector
├── face_miner.py      # Face extraction engine
├── reface_engine.py   # Face swap engine
├── undress_engine.py  # AI clothes transformation (uses venv_ai)
├── dashboard.py       # Streamlit UI
├── run_dashboard.bat  # Quick start script
├── venv/              # Main virtual environment (Python 3.13)
├── venv_ai/           # AI virtual environment (Python 3.10)
└── extracted_faces/   # Output directory for face images
```

## Configuration

Edit `.env` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | localhost | PostgreSQL host |
| `DB_PORT` | 5432 | PostgreSQL port |
| `DB_USER` | postgres | Database user |
| `DB_PASS` | - | Database password |
| `DB_NAME` | antigravity_local | Database name |
| `VIDEO_FOLDER` | ./videos | Input video directory |
| `FRAME_INTERVAL` | 1.0 | Seconds between frame extractions |
| `QUALITY_THRESHOLD` | 0.6 | Minimum face quality (0-1) |
| `DUPLICATE_THRESHOLD` | 0.05 | Max cosine distance for duplicates |

## Dashboard Features

### Gallery View
- Browse faces grouped by person
- View unassigned faces
- Create new person groups

### Reface
- Swap faces in images and videos
- Use any person from your gallery as source

### Magic Undress
- Clothes restyle on the background job queue
- Upload a still, or pick a gallery person whose source is a still photo

### Merge People
- Combine duplicate person clusters
- Visual preview of faces before merging

### Export for LoRA
- Select persons to export
- Generates image + caption files
- Compatible with Kohya_ss, LoRA training tools

## GPU Acceleration

The tool automatically detects CUDA and uses GPU when available. For Advanced Optimus/MUX switch laptops, ensure:

1. NVIDIA Control Panel is set to use dedicated GPU for Python
2. CUDA Toolkit is installed (for onnxruntime-gpu)

## License

MIT License
