"""Small LAN-only UDP discovery. Announcements never carry credentials or pins."""
import ipaddress
import json
import re
import socket
import threading
import time

SERVICE = 'antigravity-mobile'
DISCOVERY_PORT = 8445


def private_v4(host):
    try:
        ip = ipaddress.IPv4Address(host)
        return any(ip in ipaddress.IPv4Network(block) for block in
                   ('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','169.254.0.0/16','127.0.0.0/8'))
    except ValueError: return False


class LanResponder:
    def __init__(self, ctx, *, bind='0.0.0.0', port=DISCOVERY_PORT, log=print):
        self.ctx, self.bind, self.port, self.log = ctx, bind, port, log
        self.socket = None
        self.thread = None
        self.stopped = threading.Event()

    def start(self):
        connection = None
        try:
            connection = socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
            connection.bind((self.bind,self.port))
            connection.settimeout(.5)
            self.socket = connection
            self.port = connection.getsockname()[1]
            self.thread = threading.Thread(target=self._run,name='lan-discovery',daemon=True)
            self.thread.start()
            return True
        except OSError as error:
            if connection: connection.close()
            self.log(f'[discovery] UDP unavailable: {error}; QR/manual connection still works.')
            return False

    def _run(self):
        window, count = time.monotonic(), 0
        while not self.stopped.is_set():
            try:
                raw, peer = self.socket.recvfrom(1025)
                if time.monotonic()-window >= 1: window,count = time.monotonic(),0
                count += 1
                if count > 20 or len(raw) > 1024 or not private_v4(peer[0]): continue
                request = json.loads(raw)
                if (not isinstance(request,dict) or request.get('service') != SERVICE
                        or request.get('version') != 1
                        or re.fullmatch(r'[a-f0-9]{32}',str(request.get('nonce',''))) is None): continue
                response = {'service':SERVICE,'version':1,'nonce':request['nonce'],
                    'server_id':self.ctx.auth.server_id,'name':self.ctx.auth.server_name[:128],
                    'port':self.ctx.api_port}
                self.socket.sendto(json.dumps(response).encode('utf-8'),peer)
            except (ValueError,UnicodeError): continue
            except socket.timeout: continue
            except OSError: break

    def stop(self):
        self.stopped.set()
        if self.socket: self.socket.close()
        if self.thread: self.thread.join(timeout=2)


class NetworkMonitor:
    def __init__(self, ctx, discovery, *, addresses, mdns=True, fixed_host=None):
        self.ctx,self.discovery,self.addresses,self.mdns,self.fixed_host = ctx,discovery,addresses,mdns,fixed_host
        self.stopped = threading.Event()
        self.thread = None
        self.previous = None

    def refresh(self):
        current = list(dict.fromkeys(([self.fixed_host] if self.fixed_host else []) + self.addresses()))
        self.ctx.host_addresses = current
        if current != self.previous:
            self.previous = current
            if self.mdns:
                self.discovery.stop()
                if current: self.discovery.start(name=self.ctx.auth.server_name,server_id=self.ctx.auth.server_id,
                    api_version=self.ctx.api_version,port=self.ctx.api_port,addresses=current)

    def start(self):
        self.refresh()
        def run():
            while not self.stopped.wait(3):
                try: self.refresh()
                except OSError: pass
        self.thread = threading.Thread(target=run,name='network-addresses',daemon=True)
        self.thread.start()

    def stop(self):
        self.stopped.set()
        if self.thread: self.thread.join(timeout=4)
