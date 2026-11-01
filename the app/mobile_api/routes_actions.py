"""Bounded CPU action ranking. No labels, media, database or GPU state retained."""
import asyncio
import json

from fastapi import APIRouter, Depends, Request
from starlette.concurrency import run_in_threadpool

from .action_matching import ActionRequestError, match_request
from .errors import bad_request
from .routes_grouping import read_limited_body


def build_actions_router(ctx, require_device):
    router = APIRouter()
    serial = asyncio.Lock()

    @router.post('/v1/actions/match')
    async def match_actions(request: Request, _=Depends(require_device)):
        raw = await read_limited_body(request, 16*1024*1024, 16*1024*1024)
        try:
            body = json.loads(raw)
        except (ValueError, UnicodeError) as error:
            raise bad_request('The action request is not valid JSON.') from error
        try:
            async with serial:
                return await run_in_threadpool(match_request, body)
        except ActionRequestError as error:
            raise bad_request(str(error)) from error
    return router
