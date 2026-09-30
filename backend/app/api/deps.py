from fastapi import Request

from app.core.config import Settings
from app.services.storage import StudyStorage


def get_storage(request: Request) -> StudyStorage:
    return request.app.state.storage


def get_app_settings(request: Request) -> Settings:
    return request.app.state.settings
