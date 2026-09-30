from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict
from pydantic import field_validator
from typing import Annotated


class Settings(BaseSettings):
    """Runtime configuration, read from environment variables / `.env`."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "AIRA Image Processing API"
    storage_dir: Path = Path("storage")
    max_upload_mb: int = 1024
    study_ttl_hours: int = 24
    cleanup_interval_minutes: int = 60

    # Modality combinations are controlled by configuration (spec §7).
    allowed_modalities: Annotated[list[str], NoDecode] = ["T2W", "DWI", "ADC"]
    required_modalities: Annotated[list[str], NoDecode] = ["T2W"]

    cors_origins: Annotated[list[str], NoDecode] = ["*"]

    # External ML Model API (Phase 3). Never exposed to the mobile client.
    ml_api_url: str | None = None
    ml_api_key: str | None = None
    ml_api_timeout_seconds: float = 300.0

    @field_validator("allowed_modalities", "required_modalities", "cors_origins", mode="before")
    @classmethod
    def _split_csv(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @property
    def max_upload_bytes(self) -> int:
        return self.max_upload_mb * 1024 * 1024


@lru_cache
def get_settings() -> Settings:
    return Settings()
