"""
Pairing: a one-time code shown on the PC, exchanged for a device token.

The PC shows a QR on a page served ONLY on 127.0.0.1 (a second, plain-HTTP listener -
see server.py; the HTTPS API never serves it). Payload:

    agmobile://pair?h=<host>&p=<port>&fp=<cert sha256>&c=<one-time code>

The phone pins `fp`, so the QR flow is MITM-proof. For manual IP entry the phone shows the
certificate fingerprint it was offered and the user compares it with the PC screen.

The code is single use, expires after `ttl` seconds and is burned after `max_attempts`
wrong guesses, so it cannot be brute-forced over the LAN.
"""

import hmac
import html
import secrets
import threading
import time
from dataclasses import dataclass
from typing import Callable, Dict, Optional, Tuple
from urllib.parse import urlencode

# no 0/O/1/I/L - the code is also typed by hand when the QR cannot be scanned
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
SCHEME = "agmobile"


class PairingError(Exception):
    def __init__(self, kind: str, message: str):
        super().__init__(message)
        self.kind = kind  # invalid | expired | locked | none
        self.message = message


@dataclass
class IssuedCode:
    code: str            # XXXX-XXXX
    expires_at: float    # wall-clock seconds
    ttl: int


def normalize_code(code: str) -> str:
    return "".join(ch for ch in (code or "").upper() if ch.isalnum())


def format_code(raw: str) -> str:
    return f"{raw[:4]}-{raw[4:]}"


def pair_payload(host: str, port: int, fingerprint: str, code: str) -> str:
    return f"{SCHEME}://pair?" + urlencode({"h": host, "p": port, "fp": fingerprint, "c": code})


def parse_payload(uri: str) -> Dict[str, str]:
    """Inverse of pair_payload (used by tests; the phone has its own Dart implementation)."""
    from urllib.parse import parse_qsl, urlsplit
    parts = urlsplit(uri)
    if parts.scheme != SCHEME or parts.netloc != "pair":
        raise ValueError(f"not a pairing URI: {uri!r}")
    return dict(parse_qsl(parts.query))


class PairingManager:
    def __init__(self, auth_store, ttl: int = 300, max_attempts: int = 5,
                 clock: Callable[[], float] = time.time):
        self.auth = auth_store
        self.ttl = ttl
        self.max_attempts = max_attempts
        self._clock = clock
        self._lock = threading.Lock()
        self._code: Optional[str] = None
        self._expires = 0.0
        self._failures = 0

    def issue(self) -> IssuedCode:
        """A fresh code; any earlier one stops working."""
        raw = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        with self._lock:
            self._code = raw
            self._expires = self._clock() + self.ttl
            self._failures = 0
        return IssuedCode(format_code(raw), self._expires, self.ttl)

    def current(self) -> Optional[IssuedCode]:
        """The active code (for the PC screen), or None if there is none / it expired / it was burned."""
        with self._lock:
            if self._code is None or self._clock() >= self._expires or self._failures >= self.max_attempts:
                return None
            return IssuedCode(format_code(self._code), self._expires, self.ttl)

    def cancel(self) -> None:
        with self._lock:
            self._code = None
            self._expires = 0.0

    def complete(self, code: str, device_name: str) -> Tuple[Dict, str]:
        """Exchange the code for a device. Returns (device incl. plain token, server_id)."""
        with self._lock:
            if self._code is None:
                raise PairingError("none", "No pairing code is active. Open the pairing page on the PC.")
            if self._failures >= self.max_attempts:
                raise PairingError("locked", "Too many wrong codes. Create a new code on the PC.")
            if self._clock() >= self._expires:
                self._code = None
                raise PairingError("expired", "The pairing code expired. Create a new code on the PC.")
            if not hmac.compare_digest(normalize_code(code), self._code):
                self._failures += 1
                left = self.max_attempts - self._failures
                raise PairingError("invalid", f"Wrong pairing code ({left} attempt{'s' if left != 1 else ''} left).")
            self._code = None  # single use
        device = self.auth.add_device(device_name)
        return device, self.auth.server_id


# --- the PC-side page ----------------------------------------------------------

def render_pair_page(*, payload: str, qr_png_b64: str, code: Optional[IssuedCode], host: str, port: int,
                     fingerprint: str, server_name: str, other_hosts, devices, notice: str = "") -> str:
    e = html.escape
    fp_groups = " ".join(fingerprint[i:i + 4] for i in range(0, len(fingerprint), 4))
    hosts = " &middot; ".join(f'<a href="/pair?h={e(h)}">{e(h)}</a>' for h in other_hosts)
    rows = "".join(
        f"<tr><td>{e(d['name'])}</td><td>{e(d['created_at'])}</td><td>{e(d['last_seen'] or 'never')}</td>"
        f"<td><form method='post' action='/pair/revoke/{e(d['id'])}'><button>Revoke</button></form></td></tr>"
        for d in devices) or "<tr><td colspan='4'>No phones paired yet.</td></tr>"
    if code is not None:
        body = f"""
        <img class="qr" alt="Pairing QR code" src="data:image/png;base64,{qr_png_b64}">
        <p class="code">{e(code.code)}</p>
        <p class="hint">Scan with Antigravity on your phone, or choose <b>Enter manually</b> and type
        <b>{e(host)}</b>, port <b>{port}</b> and this code. Valid for <span id="left">{code.ttl}</span> s.</p>"""
    else:
        body = "<p class='hint'>No active code (it expired, was used, or was burned by wrong guesses).</p>"
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pair a phone - {e(server_name)}</title>
<style>
 :root {{ color-scheme: dark; }}
 body {{ font: 16px system-ui, sans-serif; background:#101114; color:#e8e9ee; margin:0; padding:32px; max-width:640px; }}
 h1 {{ font-size:22px; }} .qr {{ width:280px; height:280px; image-rendering:pixelated; background:#fff; padding:12px; border-radius:12px; }}
 .code {{ font:700 34px ui-monospace,Consolas,monospace; letter-spacing:4px; margin:12px 0 4px; }}
 .hint {{ color:#a7a9b4; }} .fp {{ font:13px ui-monospace,Consolas,monospace; color:#a7a9b4; word-break:break-all; }}
 button {{ background:#3b82f6; color:#fff; border:0; border-radius:8px; padding:8px 14px; font-size:15px; cursor:pointer; }}
 table {{ width:100%; border-collapse:collapse; margin-top:8px; }} td,th {{ text-align:left; padding:6px 4px; border-bottom:1px solid #2a2c33; font-size:14px; }}
 .notice {{ background:#243b2c; padding:8px 12px; border-radius:8px; }} a {{ color:#7aa7ff; }}
</style></head><body>
<h1>Pair a phone with {e(server_name)}</h1>
{f"<p class='notice'>{e(notice)}</p>" if notice else ""}
{body}
<form method="post" action="/pair/new"><button>New code</button></form>
<p class="hint">Address in the QR: <b>{e(host)}:{port}</b>. Other addresses of this PC: {hosts or "none found"}</p>
<p class="hint">Certificate fingerprint (SHA-256) - the phone shows this if you pair by typing the address:</p>
<p class="fp">{e(fp_groups)}</p>
<h1>Paired phones</h1>
<table><tr><th>Name</th><th>Paired</th><th>Last seen</th><th></th></tr>{rows}</table>
<script>
 var s = {code.ttl if code else 0}; var el = document.getElementById('left');
 if (el) setInterval(function () {{ s -= 1; if (s <= 0) location.reload(); else el.textContent = s; }}, 1000);
</script>
</body></html>"""
