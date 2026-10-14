"""
Server identity + paired devices (mobile_workspace/devices.json) and the bearer-token check.

Tokens are random 160-bit values handed to the phone once; only their SHA-256 is stored, so
a copy of devices.json cannot be used to call the API.
"""

import hashlib
import hmac
import json
import os
import secrets
import socket
import threading
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from .errors import unauthorized

TOKEN_PREFIX = "agm_"
LAST_SEEN_WRITE_INTERVAL = 60.0  # seconds between last_seen writes per device


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def new_token() -> str:
    return TOKEN_PREFIX + secrets.token_hex(20)


class AuthStore:
    def __init__(self, path, server_name: Optional[str] = None):
        self.path = Path(path)
        self._lock = threading.RLock()
        self._last_write: Dict[str, float] = {}
        self._data = self._load()
        changed = False
        if not self._data.get("server_id"):
            self._data["server_id"] = "srv_" + uuid.uuid4().hex[:8]
            changed = True
        if server_name and self._data.get("server_name") != server_name:
            self._data["server_name"] = server_name
            changed = True
        if not self._data.get("server_name"):
            self._data["server_name"] = (socket.gethostname() or "Antigravity PC")[:64]
            changed = True
        self._data.setdefault("devices", [])
        if changed:
            self._save()

    # --- persistence ------------------------------------------------------

    def _load(self) -> Dict:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def _save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_name(self.path.name + ".tmp")
        tmp.write_text(json.dumps(self._data, indent=2), encoding="utf-8")
        os.replace(tmp, self.path)

    # --- identity ---------------------------------------------------------

    @property
    def server_id(self) -> str:
        return self._data["server_id"]

    @property
    def server_name(self) -> str:
        return self._data["server_name"]

    # --- devices ----------------------------------------------------------

    def add_device(self, name: str) -> Dict:
        """Register a device and return {"token": <plain, shown once>, **public device fields}."""
        token = new_token()
        device = {
            "id": "dev_" + uuid.uuid4().hex[:8],
            "name": (name or "Phone").strip()[:64] or "Phone",
            "token_hash": hash_token(token),
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "last_seen": None,
        }
        with self._lock:
            self._data["devices"].append(device)
            self._save()
        return {"token": token, **self._public(device)}

    def authenticate(self, token: str) -> Optional[Dict]:
        if not token or not token.startswith(TOKEN_PREFIX):
            return None
        digest = hash_token(token)
        with self._lock:
            found = None
            for device in self._data["devices"]:  # compare every entry: no early exit on a prefix match
                if hmac.compare_digest(device["token_hash"], digest):
                    found = device
            if found is None:
                return None
            now = time.monotonic()
            found['last_seen'] = datetime.now().isoformat(timespec='seconds')
            if now - self._last_write.get(found["id"], -1e9) >= LAST_SEEN_WRITE_INTERVAL:
                self._last_write[found["id"]] = now
                self._save()
            return self._public(found)

    def revoke(self, device_id: str) -> bool:
        with self._lock:
            before = len(self._data["devices"])
            self._data["devices"] = [d for d in self._data["devices"] if d["id"] != device_id]
            if len(self._data["devices"]) != before:
                self._save()
                return True
            return False

    def has_device(self, device_id: str) -> bool:
        with self._lock:
            return any(d['id'] == device_id for d in self._data['devices'])

    def rename(self, device_id: str, name: str) -> bool:
        name = name.strip()
        if not name or len(name) > 64:
            raise ValueError('Use a device name between 1 and 64 characters.')
        with self._lock:
            for device in self._data['devices']:
                if device['id'] == device_id:
                    device['name'] = name
                    self._save()
                    return True
            return False

    def devices(self) -> List[Dict]:
        with self._lock:
            return [self._public(d) for d in self._data["devices"]]

    @staticmethod
    def _public(device: Dict) -> Dict:
        return {k: device[k] for k in ("id", "name", "created_at", "last_seen")}


def bearer_token(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    scheme, _, value = authorization.partition(" ")
    if scheme.lower() != "bearer" or not value.strip():
        return None
    return value.strip()


def authenticate_header(store: AuthStore, authorization: Optional[str]) -> Dict:
    """The device behind an Authorization header, or raises the 401 envelope."""
    device = store.authenticate(bearer_token(authorization) or "")
    if device is None:
        raise unauthorized()
    return device
