from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core import errors
from app.core.config import Settings
from app.services import users
from app.services.jobs import JobService
from app.services.storage import StudyStorage

_bearer = HTTPBearer(auto_error=False)


def get_storage(request: Request) -> StudyStorage:
    return request.app.state.storage


def get_jobs(request: Request) -> JobService:
    return request.app.state.jobs


def get_app_settings(request: Request) -> Settings:
    return request.app.state.settings


def get_current_user_id(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> str:
    """The anonymous user behind the bearer token; 401 when it is missing or unknown."""
    user_id = users.authenticate(request.app.state.db, credentials.credentials) if credentials else None
    if user_id is None:
        raise errors.unauthorized()
    return user_id


CurrentUser = Annotated[str, Depends(get_current_user_id)]


def limit_ip(name: str):
    """Rate limit by client address (for the unauthenticated registration endpoint)."""

    def check(request: Request) -> None:
        settings: Settings = request.app.state.settings
        host = request.client.host if request.client else "unknown"
        request.app.state.limiter.check(
            f"{name}:{host}", getattr(settings, f"rate_limit_{name}"), settings.rate_limit_window_seconds
        )

    return Depends(check)


def limit_user(name: str):
    """Rate limit by user, for the endpoints that cost CPU, memory or disk."""

    def check(request: Request, user_id: CurrentUser) -> None:
        settings: Settings = request.app.state.settings
        request.app.state.limiter.check(
            f"{name}:{user_id}", getattr(settings, f"rate_limit_{name}"), settings.rate_limit_window_seconds
        )

    return Depends(check)
