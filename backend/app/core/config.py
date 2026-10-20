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
    # SQLAlchemy URL, e.g. mysql+pymysql://user:password@host:3306/aira. Empty: SQLite file in the storage dir.
    database_url: str | None = None
    max_upload_mb: int = 1024
    study_ttl_hours: int = 24
    cleanup_interval_minutes: int = 60

    # Modality combinations are controlled by configuration (spec §7).
    allowed_modalities: Annotated[list[str], NoDecode] = ["T2W", "DWI", "ADC"]
    required_modalities: Annotated[list[str], NoDecode] = ["T2W"]

    # The mobile app is not a browser and needs no CORS. List web origins here only if a web client exists.
    cors_origins: Annotated[list[str], NoDecode] = []
    # /docs, /redoc and /openapi.json describe every endpoint: off unless asked for (DOCS_ENABLED=true in development).
    docs_enabled: bool = False

    # Abuse limits. Per client IP for registration, per user for everything else (requests per window).
    rate_limit_window_seconds: int = 60
    rate_limit_register: int = 10
    rate_limit_upload: int = 6
    rate_limit_segment: int = 6
    rate_limit_edit: int = 120  # save + refine
    max_studies_per_user: int = 10
    max_active_jobs_per_user: int = 2
    max_upload_files: int = 5000
    max_zip_members: int = 10000
    # Decoded volumes are held in memory as float32: 64M voxels is 256 MB.
    max_volume_voxels: int = 64_000_000

    # Bundled segmentation model. Swap `model_path` (same architecture) to replace the model.
    model_path: Path = Path("models/prostate_segmentation.pth")
    model_name: str = "Multi-branch Dense U-Net (PI-CAI lesion)"
    model_note: str = "Experimental model, validation Dice about 0.2. Not for clinical use."

    # Mask refinement (edge fitting of hand edits). Only methods listed here can be requested.
    refine_enabled_methods: Annotated[list[str], NoDecode] = ["random_walker"]
    refine_timeout_seconds: float = 5.0

    # External ML Model API (Phase 3). Never exposed to the mobile client.
    ml_api_url: str | None = None
    ml_api_key: str | None = None
    ml_api_timeout_seconds: float = 300.0

    @field_validator("allowed_modalities", "required_modalities", "cors_origins", "refine_enabled_methods", mode="before")
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
