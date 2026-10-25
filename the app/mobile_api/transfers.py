"""Bounded result streaming; retain Starlette's ownership-independent Range support."""
from fastapi.responses import FileResponse


class ResultFileResponse(FileResponse):
    # Default 64 KiB reads require a thread-pool hop per block on Windows.
    # One MiB reduces scheduling overhead without loading a whole video in RAM.
    chunk_size = 1024 * 1024
