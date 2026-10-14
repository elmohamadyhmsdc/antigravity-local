"""
Antigravity Mobile API - a STATELESS compute server for the phone app.

The phone owns every piece of user data. This package keeps only:
  * paired devices + its own TLS certificate (mobile_workspace/devices.json, tls/)
  * an evictable blob cache and per-job scratch dirs (mobile_workspace/, wiped on start)

Hard rules (enforced by test_mobile_stateless.py):
  * never import database / JsonDatabase or anything that does, never read data/
  * never unpickle anything received over the network

The contract is contract/openapi.yaml; golden fixtures live in contract/fixtures.
"""

import sys
from pathlib import Path

APP_DIR = Path(__file__).resolve().parents[1]  # the app/
if str(APP_DIR) not in sys.path:  # the engines (analysis, face_quality, ...) are top-level modules there
    sys.path.insert(0, str(APP_DIR))

API_VERSION = "1.0.0"
EMBEDDING_MODEL_ID = "buffalo_l@1"
EMBEDDING_DIM = 512
