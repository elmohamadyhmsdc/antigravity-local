"""
HEAD/PUT /v1/blobs/{sha256} - content-addressed, hash-verified, resumable uploads.

  HEAD  200 + Content-Length          cached
        404 + Upload-Offset           not cached; Upload-Offset = bytes of a partial upload we hold (0 if none)
  PUT   no Content-Range              the whole blob in one request (restarts any partial)
        Content-Range: bytes a-b/N    one chunk; `a` must equal the current Upload-Offset
        201 stored | 202 chunk accepted (Upload-Offset = new offset) | 204 already cached
        408 upload_stalled (+Upload-Offset) | 409 offset_mismatch (+Upload-Offset) | 413 too_large
        422 hash_mismatch

The server cache is evictable: a blob that disappears is simply uploaded again.

A phone that loses Wi-Fi mid-chunk leaves a half-open connection the server never hears close.
Its PUT holds this blob's lock, so the body is read with an idle timeout: the bytes that did
arrive stay in the partial file and the phone's retry continues from Upload-Offset instead of
queueing forever behind a dead request.
"""

import asyncio
import hashlib
import re
from typing import Callable, Dict, Optional, Tuple

from fastapi import APIRouter, Depends, Path, Request, Response

from .errors import ApiError, bad_request

SHA_PATTERN = r"^[0-9a-f]{64}$"
BODY_IDLE_SECONDS = 30.0  # no body bytes for this long = the sender is gone
_RANGE_RE = re.compile(r"^bytes (\d+)-(\d+)/(\d+)$")


def _parse_content_range(value: str) -> Tuple[int, int, int]:
    m = _RANGE_RE.match(value.strip())
    if not m:
        raise bad_request("Content-Range must look like 'bytes <start>-<end>/<total>'")
    start, end, total = (int(g) for g in m.groups())
    if start > end or end >= total:
        raise bad_request("Content-Range is inconsistent")
    return start, end, total


class _UploadState:
    """Running hash of a partial upload (so a chunk does not re-read the whole file)."""

    def __init__(self):
        self.hasher = hashlib.sha256()
        self.offset = 0


def build_blob_router(ctx, require_device: Callable) -> APIRouter:
    router = APIRouter()
    ws = ctx.workspace
    locks: Dict[str, asyncio.Lock] = {}
    states: Dict[str, _UploadState] = {}

    def state_for(sha: str, offset: int) -> _UploadState:
        st = states.get(sha)
        if st is not None and st.offset == offset:
            return st
        st = _UploadState()  # unknown or out of step (e.g. after a dropped connection): rehash the partial file
        if offset:
            with open(ws.partial_path(sha), "rb") as f:
                for block in iter(lambda: f.read(1 << 20), b""):
                    st.hasher.update(block)
        st.offset = offset
        states[sha] = st
        return st

    @router.head("/v1/blobs/{sha256}")
    async def head_blob(sha256: str = Path(pattern=SHA_PATTERN), _: dict = Depends(require_device)):
        size = ws.blob_size(sha256)
        if size is None:
            return Response(status_code=404, headers={"Upload-Offset": str(ws.partial_size(sha256))})
        ws.touch_blob(sha256)
        return Response(status_code=200, headers={"Content-Length": str(size)})

    @router.put("/v1/blobs/{sha256}")
    async def put_blob(request: Request, sha256: str = Path(pattern=SHA_PATTERN), _: dict = Depends(require_device)):
        if ws.has_blob(sha256):
            ws.touch_blob(sha256)
            return Response(status_code=204)

        header = request.headers.get("content-range")
        if header:
            start, end, total = _parse_content_range(header)
        else:
            declared = request.headers.get("content-length")
            start, end, total = 0, None, (int(declared) if declared and declared.isdigit() else None)
        if total is not None and total > ws.max_upload_bytes:
            raise ApiError(413, "too_large", f"Blobs are limited to {ws.max_upload_bytes // (1024 * 1024)} MB.")
        if total is not None and total > ws.blob_cache_bytes:
            raise ApiError(413, "too_large", "The blob is larger than the server's cache.")

        lock = locks.setdefault(sha256, asyncio.Lock())
        async with lock:
            if ws.has_blob(sha256):  # another request finished it while we waited
                return Response(status_code=204)
            offset = ws.partial_size(sha256)
            if header is None:
                ws.discard_partial(sha256)
                offset = 0
            elif start != offset:
                raise ApiError(409, "offset_mismatch",
                               f"The server holds {offset} bytes of this upload, not {start}.", retryable=True,
                               headers={"Upload-Offset": str(offset)})
            st = state_for(sha256, offset)

            received = 0
            path = ws.partial_path(sha256)
            body = request.stream().__aiter__()
            with open(path, "ab") as out:
                while True:
                    try:
                        chunk = await asyncio.wait_for(body.__anext__(), BODY_IDLE_SECONDS)
                    except StopAsyncIteration:
                        break
                    except asyncio.TimeoutError:
                        # st still matches the file (hash and offset advance per written block).
                        raise ApiError(408, "upload_stalled", "No upload data arrived; resume from Upload-Offset.",
                                       retryable=True, headers={"Upload-Offset": str(st.offset)})
                    if not chunk:
                        continue
                    received += len(chunk)
                    if st.offset + len(chunk) > ws.max_upload_bytes or (total is not None and st.offset + len(chunk) > total):
                        out.close()
                        ws.discard_partial(sha256)
                        states.pop(sha256, None)
                        raise ApiError(413, "too_large", "More data than declared or allowed.")
                    out.write(chunk)
                    st.hasher.update(chunk)
                    st.offset += len(chunk)

            if end is not None and received != end - start + 1:
                states.pop(sha256, None)  # the partial file stays; the phone resumes from Upload-Offset
                raise bad_request(f"Content-Range promised {end - start + 1} bytes but {received} arrived")
            complete = (total is None) or st.offset == total
            if not complete:
                return Response(status_code=202, headers={"Upload-Offset": str(st.offset)})

            states.pop(sha256, None)
            if st.hasher.hexdigest() != sha256:
                ws.discard_partial(sha256)
                raise ApiError(422, "hash_mismatch", "The uploaded bytes do not hash to the blob id.")
            ws.commit_partial(sha256)
            return Response(status_code=201)

    return router
