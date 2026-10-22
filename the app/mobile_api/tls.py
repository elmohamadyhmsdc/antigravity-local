"""
Self-signed TLS certificate, generated on first run and kept in mobile_workspace/tls/.

The phone does NOT trust a CA: it pins the certificate's SHA-256 fingerprint (from the
pairing QR), so hostnames/SANs are informational and the certificate is NOT regenerated when
the PC's IP changes (that would silently break every paired phone). It is regenerated only if
it is missing, unreadable or about to expire - phones then have to pair again.
"""

import datetime as dt
import hashlib
import ipaddress
import socket
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

CERT_NAME = "server.crt"
KEY_NAME = "server.key"
VALID_DAYS = 365 * 5
RENEW_BEFORE_DAYS = 30


@dataclass(frozen=True)
class CertInfo:
    cert_path: Path
    key_path: Path
    fingerprint: str  # SHA-256 of the DER certificate, lowercase hex, 64 chars


def fingerprint_of_cert(cert: x509.Certificate) -> str:
    return hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest()


def fingerprint_of_pem_file(path) -> str:
    cert = x509.load_pem_x509_certificate(Path(path).read_bytes())
    return fingerprint_of_cert(cert)


def _generate(cert_path: Path, key_path: Path, common_name: str, hosts: Iterable[str]) -> None:
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name[:64]),
                      x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Your Gallery")])
    sans: List[x509.GeneralName] = [x509.DNSName("localhost")]
    for h in dict.fromkeys(hosts):
        try:
            sans.append(x509.IPAddress(ipaddress.ip_address(h)))
        except ValueError:
            if h and h != "localhost":
                sans.append(x509.DNSName(h))
    now = dt.datetime.now(dt.timezone.utc)
    cert = (x509.CertificateBuilder()
            .subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - dt.timedelta(days=1))
            .not_valid_after(now + dt.timedelta(days=VALID_DAYS))
            .add_extension(x509.SubjectAlternativeName(sans), critical=False)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
            .sign(key, hashes.SHA256()))
    cert_path.parent.mkdir(parents=True, exist_ok=True)
    key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                           serialization.NoEncryption()))
    cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))


def _usable(cert_path: Path, key_path: Path) -> bool:
    try:
        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        serialization.load_pem_private_key(key_path.read_bytes(), password=None)
        expires = cert.not_valid_after_utc
        return expires - dt.datetime.now(dt.timezone.utc) > dt.timedelta(days=RENEW_BEFORE_DAYS)
    except Exception:
        return False


def ensure_cert(tls_dir, hosts: Iterable[str] = (), common_name: str = "") -> CertInfo:
    """Load the persisted certificate or generate one. `hosts` (IPs / DNS names) go into the SANs."""
    tls_dir = Path(tls_dir)
    cert_path, key_path = tls_dir / CERT_NAME, tls_dir / KEY_NAME
    if not (cert_path.is_file() and key_path.is_file() and _usable(cert_path, key_path)):
        hostname = socket.gethostname()
        _generate(cert_path, key_path, common_name or hostname or "Your Gallery PC",
                  ["127.0.0.1", "::1", "10.0.2.2", hostname, *hosts])  # 10.0.2.2 = Android emulator -> host
    return CertInfo(cert_path, key_path, fingerprint_of_pem_file(cert_path))
