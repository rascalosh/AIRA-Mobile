import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator

from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware

from app.api import health, jobs, masks, resources, studies, users
from app.clients.local_model_client import LocalTorchClient
from app.core.config import Settings, get_settings
from app.core.errors import register_exception_handlers
from app.core.logging import configure_logging
from app.core.ratelimit import RateLimiter
from app.db.session import Database
from app.services.jobs import JobService
from app.services.segmentation_service import SegmentationService
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
        await run_in_threadpool(app.state.jobs.fail_interrupted)
        await run_in_threadpool(storage.cleanup_expired)
        task = asyncio.create_task(_periodic_cleanup(storage, settings.cleanup_interval_minutes))
        try:
            yield
        finally:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task
            app.state.jobs.shutdown()

    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        description="DICOM handling and DICOM → NIfTI conversion for AI-assisted prostate MRI "
        "segmentation visualization. Not intended for diagnosis.",
        lifespan=lifespan,
        docs_url="/docs" if settings.docs_enabled else None,
        redoc_url="/redoc" if settings.docs_enabled else None,
        openapi_url="/openapi.json" if settings.docs_enabled else None,
    )
    app.state.settings = settings
    settings.storage_dir.mkdir(parents=True, exist_ok=True)
    app.state.db = Database(settings.database_url or f"sqlite:///{(settings.storage_dir / 'aira.db').as_posix()}")
    app.state.db.create_all()
    app.state.storage = StudyStorage(settings.storage_dir, settings.study_ttl_hours, app.state.db)
    segmentation = SegmentationService(LocalTorchClient(settings.model_path), app.state.storage, settings)
    app.state.jobs = JobService(app.state.db, app.state.storage, segmentation, settings.max_active_jobs_per_user)
    app.state.limiter = RateLimiter()

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Frame-Options"] = "DENY"
        # Medical images and results: never stored by browsers or intermediaries.
        response.headers["Cache-Control"] = "no-store"
        return response

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "DELETE"],
            allow_headers=["Authorization", "Content-Type"],
        )
    register_exception_handlers(app)
    app.include_router(health.router)
    app.include_router(users.router)
    app.include_router(jobs.router)
    app.include_router(studies.router)
    app.include_router(resources.router)
    app.include_router(masks.router)
    return app


app = create_app()
