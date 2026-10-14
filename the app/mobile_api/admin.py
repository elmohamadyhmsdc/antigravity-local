"""PC-only controls shared by the pairing page and the Streamlit dashboard."""

import hmac
import time
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from .pairing import pair_payload

PROTOCOL = 'antigravity-mobile-control-v1'
CONTROL_FILE = 'control.json'


def pause_device_jobs(ctx, device_id):
    count = 0
    with ctx.jobs_lock:
        for manager in (ctx.video_jobs, ctx.studio_jobs):
            with manager.lock:
                for job in list(manager.jobs.values()):
                    if job['owner'] == device_id and job['status'] in ('running','queued'):
                        manager.control(job['job_id'],{'id':device_id})
                        count += 1
    return count


def revoke_device(ctx, device_id):
    with ctx.jobs_lock:
        removed = ctx.auth.revoke(device_id)
        if removed: ctx.pairing.cancel()
        return removed, pause_device_jobs(ctx,device_id) if removed else 0


def recently_seen(value, *, now=None):
    if not value: return False
    try:
        seen = datetime.fromisoformat(value).astimezone(timezone.utc)
        age = (time.time() if now is None else now) - seen.timestamp()
        return 0 <= age <= 120
    except (ValueError,TypeError):
        return False


def build_admin_router(ctx):
    router = APIRouter(prefix='/admin')

    def require_admin(request: Request):
        supplied = request.headers.get('x-antigravity-admin','')
        if not supplied or not hmac.compare_digest(supplied.encode('utf-8'),ctx.admin_token.encode('utf-8')):
            raise HTTPException(403,'PC administration token required.')

    def choose_host(host, strict=False):
        addresses = list(dict.fromkeys([*ctx.host_addresses,'127.0.0.1','10.0.2.2']))
        if ctx.bind_address in ('127.0.0.1','localhost','::1'): addresses = ['127.0.0.1','10.0.2.2']
        elif ctx.bind_address not in ('0.0.0.0','::'): addresses = [ctx.bind_address]
        if strict and host is not None and host not in addresses:
            raise HTTPException(400,'Choose an address offered by this PC.')
        return host if host in addresses else addresses[0], addresses

    def snapshot(host=None):
        from .discovery import address_labels
        chosen, addresses = choose_host(host)
        current = ctx.pairing.current()
        counts = {}
        for manager in (ctx.video_jobs, ctx.studio_jobs):
            with manager.lock:
                for job in manager.jobs.values():
                    if job['status'] in ('queued','running'):
                        counts[job['owner']] = counts.get(job['owner'],0) + 1
        devices = [dict(d,active_recently=recently_seen(d['last_seen']),active_jobs=counts.get(d['id'],0))
                   for d in ctx.auth.devices()]
        return {'protocol':PROTOCOL,'server_id':ctx.auth.server_id,'name':ctx.auth.server_name,
                'api_ready':ctx.api_ready,'api_port':ctx.api_port,'addresses':addresses,'host':chosen,
                'fingerprint':ctx.cert.fingerprint if ctx.cert else '',
                'network':{'bind':ctx.bind_address,'discovery_port':ctx.discovery_port,
                    'discovery_ready':ctx.lan_discovery_ready,'labels':address_labels()},
                'devices':devices,'pairing':None if current is None else {
                    'code':current.code,'expires_at':current.expires_at,
                    'remaining_seconds':max(0,int(current.expires_at-ctx.pairing._clock())),
                    'payload':pair_payload(chosen,ctx.api_port,ctx.cert.fingerprint if ctx.cert else '',current.code)}}

    @router.get('/status',dependencies=[Depends(require_admin)])
    def status(host: str | None = None):
        return snapshot(host)

    class PairOptions(BaseModel):
        host: str | None = Field(default=None,max_length=253)

    @router.post('/pairing',dependencies=[Depends(require_admin)])
    def issue(body: PairOptions):
        choose_host(body.host,strict=True)
        ctx.pairing.issue()
        return snapshot(body.host)

    @router.post('/pairing/cancel',dependencies=[Depends(require_admin)])
    def cancel():
        ctx.pairing.cancel()
        return {'ok':True}

    class DeviceName(BaseModel):
        name: str = Field(min_length=1,max_length=64)

    @router.post('/devices/{device_id}/rename',dependencies=[Depends(require_admin)])
    def rename(device_id: str, body: DeviceName):
        try:
            renamed = ctx.auth.rename(device_id,body.name)
        except ValueError as error:
            raise HTTPException(400,str(error))
        if not renamed: raise HTTPException(404,'Device not found.')
        return {'ok':True}

    @router.post('/devices/{device_id}/revoke',dependencies=[Depends(require_admin)])
    def revoke(device_id: str):
        removed, paused = revoke_device(ctx,device_id)
        if not removed: raise HTTPException(404,'Device not found.')
        return {'ok':True,'paused_jobs':paused}

    @router.post('/devices/revoke-all',dependencies=[Depends(require_admin)])
    def revoke_all():
        count = 0
        with ctx.jobs_lock:
            ctx.pairing.cancel()
            for device in ctx.auth.devices():
                removed, _ = revoke_device(ctx,device['id'])
                count += int(removed)
        return {'ok':True,'revoked':count}

    @router.post('/shutdown',dependencies=[Depends(require_admin)])
    def shutdown():
        if ctx.shutdown is None: raise HTTPException(409,'This server cannot be stopped from the dashboard.')
        import threading
        timer = threading.Timer(.2,ctx.shutdown)
        timer.daemon = True
        timer.start()
        return {'ok':True}

    return router
