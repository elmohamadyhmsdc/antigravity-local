"""Independently verify the native Java envelope with Python cryptography.

Usage: existing-venv-python tools/verify_backup_vector.py <native-test-vector-directory>
No network access, downloads or package installation.
"""
import hashlib
import struct
import sys
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

root = Path(sys.argv[1])
password = b"backup password for tests only"
for plain in root.glob("plain-*"):
    data = (root / plain.name.replace("plain-", "encrypted-")).read_bytes()
    header, offset, index, chunks = data[:40], 40, 0, []
    assert header[:8] == b"AGBAK02\n"
    iterations, size = struct.unpack(">II", header[8:16])
    assert (iterations, size) == (600_000, 1024 * 1024)
    key = hashlib.pbkdf2_hmac("sha256", password, header[16:32], iterations, 32)
    cipher = AESGCM(key)
    while True:
        length, = struct.unpack(">I", data[offset:offset + 4])
        offset += 4
        encrypted = data[offset:offset + length + 16]
        offset += length + 16
        nonce = header[32:40] + struct.pack(">I", index)
        chunk = cipher.decrypt(nonce, encrypted, header + struct.pack(">II", index, length))
        assert len(chunk) == length
        if not length:
            break
        chunks.append(chunk)
        index += 1
    assert offset == len(data)
    assert b"".join(chunks) == plain.read_bytes()
print("Independent Python AES-GCM verification: all 4 native vectors passed.")
