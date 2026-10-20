"""Segmentation jobs: recorded in the database and run one at a time on a background thread.

ponytail: the queue lives in this process (one worker: the model is CPU-heavy). Run a single API process;
move to a real task queue (Celery/RQ) before scaling out.
"""

import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from sqlalchemy import func, select, update

from app.core import errors
from app.db.models import JobRow
from app.db.session import Database
from app.models.job import ACTIVE_JOB_STATUSES, JobRecord, JobStatus
from app.models.study import StudyRecord
from app.services.segmentation_service import SegmentationService
from app.services.storage import StudyStorage, new_id, utc_now

logger = logging.getLogger(__name__)

KIND = "segmentation"


def _aware(value: datetime | None) -> datetime | None:
    return value.replace(tzinfo=timezone.utc) if value else None


def _record(row: JobRow) -> JobRecord:
    return JobRecord(
        job_id=row.id,
        study_id=row.study_id,
        kind=row.kind,
        status=JobStatus(row.status),
        error_code=row.error_code,
        error_message=row.error_message,
        mask_version_id=row.mask_version_id,
        created_at=_aware(row.created_at),
        started_at=_aware(row.started_at),
        finished_at=_aware(row.finished_at),
    )


class JobService:
    def __init__(
        self, db: Database, storage: StudyStorage, segmentation: SegmentationService, max_active_per_user: int = 2
    ) -> None:
        self.max_active_per_user = max_active_per_user
        self.db = db
        self.storage = storage
        self.segmentation = segmentation
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="segmentation")

    def shutdown(self) -> None:
        self._pool.shutdown(wait=False, cancel_futures=True)

    def fail_interrupted(self) -> int:
        """Jobs left queued/running by a previous process will never finish: mark them failed."""
        with self.db.session() as session:
            result = session.execute(
                update(JobRow)
                .where(JobRow.status.in_(ACTIVE_JOB_STATUSES))
                .values(
                    status=JobStatus.FAILED.value,
                    error_code="JOB_INTERRUPTED",
                    error_message="The server restarted before this job finished. Please run it again.",
                    finished_at=utc_now(),
                )
            )
            return result.rowcount

    def get(self, job_id: str, user_id: str) -> JobRecord:
        with self.db.session() as session:
            row = session.get(JobRow, job_id)
            if row is None or row.user_id != user_id:
                raise errors.job_not_found()
            return _record(row)

    def has_active(self, study_id: str) -> bool:
        with self.db.session() as session:
            found = session.scalar(
                select(JobRow.id).where(JobRow.study_id == study_id, JobRow.status.in_(ACTIVE_JOB_STATUSES)).limit(1)
            )
            return found is not None

    def start_segmentation(self, study: StudyRecord, user_id: str) -> JobRecord:
        """Queue a segmentation job (or return the study's active/finished one). Bad input fails fast."""
        self.segmentation.check(study)
        ai = study.ai_mask
        with self.db.session() as session:
            active = session.scalar(
                select(JobRow).where(JobRow.study_id == study.study_id, JobRow.status.in_(ACTIVE_JOB_STATUSES))
            )
            if active is not None:
                return _record(active)
            if ai is None:
                busy = session.scalar(
                    select(func.count()).select_from(JobRow).where(
                        JobRow.user_id == user_id, JobRow.status.in_(ACTIVE_JOB_STATUSES)
                    )
                )
                if (busy or 0) >= self.max_active_per_user:
                    raise errors.quota_exceeded("Too many segmentations are running. Wait for one to finish.")
            now = utc_now()
            row = JobRow(
                id=new_id(),
                study_id=study.study_id,
                user_id=user_id,
                kind=KIND,
                status=JobStatus.COMPLETED.value if ai else JobStatus.QUEUED.value,
                mask_version_id=ai.version_id if ai else None,
                created_at=now,
                finished_at=now if ai else None,
            )
            session.add(row)
            session.flush()
            record = _record(row)
        if ai is None:
            self._pool.submit(self._run, record.job_id, study.study_id, user_id)
        return record

    def _update(self, job_id: str, **values) -> None:
        with self.db.session() as session:
            session.execute(update(JobRow).where(JobRow.id == job_id).values(**values))

    def _fail(self, job_id: str, error: errors.AppError) -> None:
        self._update(
            job_id,
            status=JobStatus.FAILED.value,
            error_code=error.code,
            error_message=error.message,
            finished_at=utc_now(),
        )

    def _run(self, job_id: str, study_id: str, user_id: str) -> None:
        self._update(job_id, status=JobStatus.RUNNING.value, started_at=utc_now())
        try:
            study = self.storage.get(study_id)
            study = asyncio.run(self.segmentation.run(study, user_id))
            self._update(
                job_id,
                status=JobStatus.COMPLETED.value,
                mask_version_id=study.ai_mask.version_id,
                finished_at=utc_now(),
            )
        except errors.AppError as exc:
            self._fail(job_id, exc)
        except Exception as exc:
            logger.warning("Job %s failed (%s)", job_id, type(exc).__name__)
            self._fail(job_id, errors.segmentation_failed())
