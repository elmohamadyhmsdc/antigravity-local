"""The error envelope: every non-2xx answer is {"error": {"code", "message", "retryable"}}."""

from typing import Any, Dict, Optional


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, retryable: bool = False,
                 headers: Optional[Dict[str, str]] = None, extra: Optional[Dict[str, Any]] = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.retryable = retryable
        self.headers = headers or {}
        self.extra = extra or {}

    def body(self) -> Dict[str, Any]:
        return {"error": {"code": self.code, "message": self.message, "retryable": self.retryable}, **self.extra}


# status -> (code, retryable) for errors raised by Starlette/FastAPI themselves (unknown route, wrong method, ...)
_HTTP_CODES = {
    400: ("bad_request", False),
    401: ("unauthorized", False),
    403: ("forbidden", False),
    404: ("not_found", False),
    405: ("bad_request", False),
    413: ("too_large", False),
    422: ("bad_request", False),
    429: ("rate_limited", True),
}


def code_for_status(status: int):
    return _HTTP_CODES.get(status, ("internal", status >= 500))


def unauthorized(message: str = "Missing or invalid device token.") -> ApiError:
    return ApiError(401, "unauthorized", message, headers={"WWW-Authenticate": "Bearer"})


def bad_request(message: str, code: str = "bad_request") -> ApiError:
    return ApiError(400, code, message)


def not_found(message: str = "Not found.") -> ApiError:
    return ApiError(404, "not_found", message)
