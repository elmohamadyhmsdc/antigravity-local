"""Local Streamlit → Mobile API control bridge. No GPU imports or Internet requests."""

import json
import os
import re
import socket
import subprocess
import threading
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

PROTOCOL = 'antigravity-mobile-control-v1'


class ControlError(RuntimeError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ControlError('The local control service returned an unexpected redirect.')


class MobileDashboardController:
    def __init__(self, app_dir=None, *, workspace=None, api_port=8443, pair_port=8444,
                 bind='0.0.0.0',mdns=True,log_dir=None):
        self.app_dir = Path(app_dir or Path(__file__).resolve().parent)
        self.workspace = Path(workspace or self.app_dir/'mobile_workspace')
        self.api_port, self.pair_port = api_port, pair_port
        self.bind, self.mdns = bind, mdns
        self.log_dir = Path(log_dir or self.app_dir/'logs')
        self._lock = threading.RLock()
        self._process = None
        self._exit_thread = None
        self._stopping = False
        self._http = build_opener(ProxyHandler({}),NoRedirect())

    def _descriptor(self):
        try:
            data = json.loads((self.workspace/'control.json').read_text(encoding='utf-8'))
        except (OSError,ValueError) as error:
            raise ControlError('The mobile server is not running.') from error
        if (data.get('protocol') != PROTOCOL or type(data.get('pair_port')) is not int
                or not 1 <= data['pair_port'] <= 65535 or data.get('api_port') != self.api_port
                or data['pair_port'] != self.pair_port
                or re.fullmatch(r'[A-Za-z0-9_-]{32,128}',str(data.get('admin_token',''))) is None):
            raise ControlError('The local mobile server control file is invalid.')
        return data

    def request(self, path, body=None):
        descriptor = self._descriptor()
        request = Request(f'http://127.0.0.1:{self.pair_port}/admin/{path}',
                          data=None if body is None else json.dumps(body).encode('utf-8'),
                          headers={'X-Antigravity-Admin':descriptor['admin_token'],'Content-Type':'application/json'})
        try:
            with self._http.open(request,timeout=2) as response:
                result = json.loads(response.read(1024*1024))
        except HTTPError as error:
            try: message = json.loads(error.read(4096)).get('detail','Local control request failed.')
            except ValueError: message = 'Local control request failed.'
            raise ControlError(str(message)) from error
        except (URLError,OSError,ValueError) as error:
            raise ControlError('The mobile server is not responding. Refresh or restart it.') from error
        return result

    @staticmethod
    def _port_busy(port):
        with socket.socket() as connection:
            connection.settimeout(.2)
            return connection.connect_ex(('127.0.0.1',port)) == 0

    def status(self, host=None):
        from urllib.parse import urlencode
        with self._lock:
            try:
                result = self.request('status'+('?' + urlencode({'host':host}) if host else ''))
                if result.get('protocol') != PROTOCOL:
                    raise ControlError('Unexpected service on the local control port.')
                result['state'] = 'stopping' if self._stopping else ('running' if result['api_ready'] else 'starting')
                return result
            except ControlError as error:
                alive = self._process is not None and self._process.poll() is None
                if alive:
                    return {'state':'stopping' if self._stopping else 'starting','message':str(error)}
                self._stopping = False
                if self._port_busy(self.pair_port) or self._port_busy(self.api_port):
                    return {'state':'external','message':'These ports are already in use. Stop the older mobile server before starting this version.'}
                if self._process is not None and self._process.returncode:
                    code = self._process.returncode
                    return {'state':'failed','message':f'Mobile server exited with code {code} (0x{code & 0xffffffff:08X}). See server diagnostics below.'}
                try:
                    exit_info = json.loads((self.log_dir/'mobile_api_exit.json').read_text(encoding='utf-8'))
                    if exit_info['api_port'] == self.api_port and exit_info['pair_port'] == self.pair_port and exit_info['code']:
                        code = exit_info['code']
                        return {'state':'failed','message':f'Mobile server exited with code {code} (0x{code & 0xffffffff:08X}) at {exit_info["at"]}. See server diagnostics below.'}
                    # An older run without an exit record may have left its control file after a native crash.
                    if (self.workspace/'control.json').exists():
                        return {'state':'failed','message':'The mobile server stopped unexpectedly. See server diagnostics below and restart it.'}
                except (OSError,ValueError,KeyError,TypeError):
                    if (self.workspace/'control.json').exists():
                        return {'state':'failed','message':'The mobile server stopped unexpectedly. See server diagnostics below and restart it.'}
                return {'state':'stopped'}

    def start(self):
        with self._lock:
            current = self.status()
            if current['state'] in ('running','starting','stopping'): return
            if current['state'] == 'external': raise ControlError(current['message'])
            python = self.app_dir/'venv'/'Scripts'/'python.exe'
            if not python.is_file(): raise ControlError('The existing PC environment was not found. Nothing was installed.')
            log = self.log_dir/'mobile_api.log'
            log.parent.mkdir(parents=True,exist_ok=True)
            with open(log,'a',encoding='utf-8') as output:
                command = [str(python),'-u','-m','mobile_api','--no-browser','--bind',self.bind,
                    '--workspace',str(self.workspace),'--port',str(self.api_port),'--pair-port',str(self.pair_port)]
                if not self.mdns: command.append('--no-mdns')
                self._process = subprocess.Popen(command,
                    cwd=str(self.app_dir),stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,
                    env=dict(os.environ,PYTHONIOENCODING='utf-8',PYTHONFAULTHANDLER='1',HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1'),
                    creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            self._stopping = False
            process = self._process
            def record_exit():
                code = process.wait()
                with self._lock:
                    if self._process is not process: return
                    record = {'code':code,'pid':process.pid,'api_port':self.api_port,'pair_port':self.pair_port,
                              'at':datetime.now(timezone.utc).isoformat()}
                    path = self.log_dir/'mobile_api_exit.json'
                    temporary = path.with_suffix('.tmp')
                    try:
                        temporary.write_text(json.dumps(record),encoding='utf-8')
                        os.replace(temporary,path)
                    except OSError: pass
            self._exit_thread = threading.Thread(target=record_exit,name='mobile-server-exit',daemon=True)
            self._exit_thread.start()

    def stop(self):
        with self._lock:
            self.request('shutdown',{})
            self._stopping = True

    def wait_stopped(self, timeout=15):
        """For local callers/tests that need the exit record fully committed."""
        if self._process is not None: self._process.wait(timeout=timeout)
        if self._exit_thread is not None: self._exit_thread.join(timeout=timeout)

    def new_code(self, host):
        return self.request('pairing',{'host':host})

    def cancel_code(self):
        self.request('pairing/cancel',{})

    def rename(self, device_id, name):
        if re.fullmatch(r'dev_[A-Za-z0-9]+',device_id) is None: raise ControlError('Invalid device ID.')
        self.request(f'devices/{device_id}/rename',{'name':name})

    def revoke(self, device_id):
        if re.fullmatch(r'dev_[A-Za-z0-9]+',device_id) is None: raise ControlError('Invalid device ID.')
        return self.request(f'devices/{device_id}/revoke',{})

    def revoke_all(self):
        return self.request('devices/revoke-all',{})

    def log_tail(self):
        try:
            with open(self.log_dir/'mobile_api.log','rb') as log:
                log.seek(0,2)
                size = log.tell()
                log.seek(max(0,size-5000))
                return log.read().decode('utf-8',errors='replace')
        except OSError:
            return ''
