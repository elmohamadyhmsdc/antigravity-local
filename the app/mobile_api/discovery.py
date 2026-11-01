"""
LAN discovery: advertises `_antigravity._tcp` over mDNS (zeroconf) so a paired phone can find
the PC again when its IP changes. mDNS is unauthenticated, so the advertisement carries NO
certificate fingerprint - the phone only uses it to locate a server whose `server_id` it already
paired with, and still pins the certificate it saved at pairing time. Manual IP entry on the
phone always works (some routers block multicast / isolate clients).
"""

import logging
import re
import socket
import threading
from typing import Callable, List, Optional

SERVICE_TYPE = "_antigravity._tcp.local."


class _SocketFailureHandler(logging.Handler):
    """Zeroconf reports async UDP errors through logging, not start()."""

    def __init__(self, addresses, failed):
        super().__init__(level=logging.WARNING)
        self.addresses = tuple(addresses)
        self.failed = failed

    def emit(self, record):
        error = record.exc_info[1] if record.exc_info else None
        if (isinstance(error, OSError) and str(record.msg).startswith('Error with socket ')
                and any(f"('{address}', 5353)" in str(record.msg) for address in self.addresses)):
            # This runs on Zeroconf's event loop. Closing it here would deadlock;
            # the network monitor owns restarts. Keep the original warning visible.
            self.failed.set()


def lan_addresses() -> List[str]:
    """IPv4 addresses of this PC that other devices could reach, primary route first."""
    found: List[str] = []
    assigned = None
    try:  # the address the OS would use to reach the internet (no packet is sent)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))
            found.append(s.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            found.append(info[4][0])
    except OSError:
        pass
    # Windows hotspot/USB adapters need not register in the PC's DNS name.
    # psutil is already provided by the dashboard; keep a stdlib fallback.
    try:
        import psutil
        stats = psutil.net_if_stats()
        assigned = set()
        for name, entries in psutil.net_if_addrs().items():
            if name in stats and not stats[name].isup: continue
            for entry in entries:
                if entry.family == socket.AF_INET:
                    found.append(entry.address)
                    assigned.add(entry.address)
    except (ImportError,OSError):
        pass
    out = []
    for ip in found:
        if (ip and not ip.startswith(("127.", "169.254.", "0.")) and ip not in out
                and (assigned is None or ip in assigned)):
            out.append(ip)
    return out


def address_labels():
    try:
        import psutil
        return {entry.address:name for name,entries in psutil.net_if_addrs().items()
                for entry in entries if entry.family == socket.AF_INET}
    except (ImportError,OSError): return {}


def _instance_name(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9 _\-]", "", name).strip() or "Your Gallery PC"
    return cleaned[:48]


class Discovery:
    """Wraps zeroconf; failures only disable discovery, never the server."""

    def __init__(self, log: Callable[[str], None] = print):
        self._log = log
        self._zc = None
        self._info = None
        self._socket_failed = threading.Event()
        self._error_handler = None

    @property
    def restart_requested(self) -> bool:
        return self._socket_failed.is_set()

    def start(self, *, name: str, server_id: str, api_version: str, port: int,
              addresses: Optional[List[str]] = None) -> bool:
        try:
            from zeroconf import ServiceInfo, Zeroconf
        except ImportError:
            self._log("[mdns] zeroconf is not installed - phones must connect by IP address")
            return False
        addresses = lan_addresses() if addresses is None else addresses
        if not addresses:
            self._log("[mdns] no LAN address found - discovery disabled")
            return False
        try:
            self._socket_failed.clear()
            self._error_handler = _SocketFailureHandler(addresses, self._socket_failed)
            logging.getLogger('zeroconf').addHandler(self._error_handler)
            instance = _instance_name(name)
            self._info = ServiceInfo(
                SERVICE_TYPE, f"{instance}.{SERVICE_TYPE}",
                addresses=[socket.inet_aton(a) for a in addresses], port=port,
                properties={"server_id": server_id, "api": api_version, "name": name[:60]},
                server=f"{_instance_name(socket.gethostname()).replace(' ', '-')}.local.")
            self._zc = Zeroconf(interfaces=addresses)
            self._zc.register_service(self._info)
            self._log(f"[mdns] advertising {instance} on {', '.join(addresses)}:{port}")
            return True
        except Exception as e:  # noqa: BLE001 - multicast can be blocked in many ways
            self._log(f"[mdns] discovery disabled: {e}")
            self.stop()
            return False

    def stop(self) -> None:
        # Unregistering sends goodbye packets, which can also fail on a lost
        # adapter. Those shutdown errors must not request another restart.
        if self._error_handler is not None:
            logging.getLogger('zeroconf').removeHandler(self._error_handler)
            self._error_handler.close()
            self._error_handler = None
        try:
            if self._zc is not None:
                if self._info is not None:
                    try:
                        self._zc.unregister_service(self._info)
                    finally:
                        self._zc.close()
                else:
                    self._zc.close()
        except Exception:  # noqa: BLE001
            pass
        self._zc = None
        self._info = None
        self._socket_failed.clear()
