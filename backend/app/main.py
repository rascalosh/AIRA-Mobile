import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator

from fastapi import FastAPI
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware

from app.api import health, resources, studies
from app.core.config import Settings, get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging
from app.services.storage import StudyStorage

logger = logging.getLogger(__name__)


async def _periodic_cleanup(storage: StudyStorage, interval_minutes: int) -> None:
    while True:
        await asyncio.sleep(interval_minutes * 60)
        try:
            await run_in_threadpool(storage.cleanup_expired)
        except OSError as exc:
            logger.warning("Cleanup failed (%s)", type(exc).__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging()

    @contextlib.asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        storage: StudyStorage = app.state.storage
        await run_in_threadpool(storage.cleanup_expired)
        task = asyncio.create_task(_periodic_cleanup(storage, settings.cleanup_interval_minutes))
        try:
            yield
        finally:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        description="DICOM handling and DICOM → NIfTI conversion for AI-assisted prostate MRI "
        "segmentation visualization. Not intended for diagnosis.",
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.storage = StudyStorage(settings.storage_dir, settings.study_ttl_hours)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    register_exception_handlers(app)
    app.include_router(health.router)
    app.include_router(studies.router)
    app.include_router(resources.router)
    return app


app = create_app()
