"""Per-study storage: metadata in the database, image and mask files on disk.

Files::

    {storage_dir}/{study_id}/
        upload/         # raw uploaded files (deleted after series grouping)
        dicom/{n}/      # valid DICOM files, one directory per series
        nifti/          # converted .nii.gz files
        segmentation/   # mask versions, {version_id}.nii.gz

Rows: users -> studies -> series, nifti_files, mask_versions, jobs (see `app.db.models`).
Every lookup is scoped to the owning user when a `user_id` is given: another user's study is "not found".
"""

import logging
import shutil
import uuid
from functools import lru_cache
from datetime import datetime, timedelta, timezone
from pathlib import Path

import nibabel as nib
import numpy as np
from sqlalchemy import exists, func, select

from app.core import errors
from app.db.models import JobRow, MaskVersionRow, NiftiRow, SeriesRow, StudyRow
from app.db.session import Database
from app.models.job import ACTIVE_JOB_STATUSES
from app.models.study import MaskVersionRecord, NiftiRecord, SeriesRecord, StudyRecord, StudyStatus

logger = logging.getLogger(__name__)


def new_id() -> str:
    return uuid.uuid4().hex


def utc_now() -> datetime:
    """Naive UTC, the form stored in the database."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _aware(value: datetime | None) -> datetime | None:
    return value.replace(tzinfo=timezone.utc) if value else None


def _naive(value: datetime) -> datetime:
    return value.astimezone(timezone.utc).replace(tzinfo=None)


@lru_cache(maxsize=512)
def _mask_slices(path: str) -> tuple[int, ...]:
    """Axial slices that contain mask. A version's file never changes, so the answer is cached by path."""
    try:
        data = np.asarray(nib.load(path).dataobj)
    except (OSError, ValueError):
        return ()
    return tuple(int(i) for i in np.nonzero(data.reshape(data.shape[0], data.shape[1], -1).any(axis=(0, 1)))[0])


def _mask_record(row: MaskVersionRow) -> MaskVersionRecord:
    return MaskVersionRecord(
        version_id=row.id,
        source=row.source,
        base_version_id=row.base_version_id,
        labels=row.labels,
        volume_ml=row.volume_ml,
        model_name=row.model_name,
        model_note=row.model_note,
        file_name=row.file_name,
        read_only=row.read_only,
        edited_slices=row.edited_slices or [],
        refined_slices=row.refined_slices or [],
        created_by=row.created_by,
        created_at=_aware(row.created_at),
    )


def _nifti_record(row: NiftiRow) -> NiftiRecord:
    return NiftiRecord(
        resource_id=row.id,
        series_id=row.series_id,
        modality=row.modality,
        shape=row.shape,
        voxel_spacing=row.voxel_spacing,
        file_name=row.file_name,
    )


def _study_record(row: StudyRow) -> StudyRecord:
    return StudyRecord(
        study_id=row.id,
        user_id=row.user_id,
        status=StudyStatus(row.status),
        created_at=_aware(row.created_at),
        updated_at=_aware(row.updated_at),
        skipped_files=row.skipped_files,
        series=[
            SeriesRecord(
                series_id=s.id,
                modality=s.modality,
                num_instances=s.num_instances,
                description=s.description,
                dir_name=s.dir_name,
            )
            for s in row.series
        ],
        nifti_files=[_nifti_record(n) for n in row.nifti_files],
        mask_versions=[_mask_record(m) for m in row.mask_versions],
    )


class StudyStorage:
    def __init__(self, root: Path, ttl_hours: int, db: Database) -> None:
        self.root = root
        self.ttl = timedelta(hours=ttl_hours)
        self.db = db
        self.root.mkdir(parents=True, exist_ok=True)

    # -- paths -----------------------------------------------------------------

    def _study_dir(self, study_id: str) -> Path:
        # IDs are generated server-side as hex UUIDs; reject anything else to prevent traversal.
        if len(study_id) != 32 or not all(c in "0123456789abcdef" for c in study_id):
            raise errors.study_not_found()
        return self.root / study_id

    def upload_dir(self, study_id: str) -> Path:
        return self._study_dir(study_id) / "upload"

    def dicom_dir(self, study_id: str) -> Path:
        return self._study_dir(study_id) / "dicom"

    def nifti_dir(self, study_id: str) -> Path:
        return self._study_dir(study_id) / "nifti"

    def segmentation_dir(self, study_id: str) -> Path:
        return self._study_dir(study_id) / "segmentation"

    # -- studies ---------------------------------------------------------------

    def create(self, user_id: str) -> StudyRecord:
        now = utc_now()
        study_id = new_id()
        with self.db.session() as session:
            session.add(
                StudyRow(id=study_id, user_id=user_id, status=StudyStatus.UPLOADED.value, created_at=now, updated_at=now)
            )
        for d in (self.upload_dir(study_id), self.dicom_dir(study_id), self.nifti_dir(study_id)):
            d.mkdir(parents=True, exist_ok=True)
        return self.get(study_id, user_id)

    def save(self, study: StudyRecord) -> None:
        """Persist status, series and converted files. Mask versions are immutable: see `add_mask_version`."""
        self._study_dir(study.study_id)
        study.touch()
        with self.db.session() as session:
            row = session.get(StudyRow, study.study_id)
            if row is None:
                raise errors.study_not_found()
            row.status = study.status.value
            row.skipped_files = study.skipped_files
            row.updated_at = _naive(study.updated_at)

            # Update in place by id: replacing rows would insert a duplicate primary key before the delete.
            existing = {s.id: s for s in row.series}
            row.series = [self._fill_series(existing.get(s.series_id) or SeriesRow(id=s.series_id), i, s)
                          for i, s in enumerate(study.series)]
            existing_nifti = {n.id: n for n in row.nifti_files}
            row.nifti_files = [self._fill_nifti(existing_nifti.get(n.resource_id) or NiftiRow(id=n.resource_id), i, n)
                               for i, n in enumerate(study.nifti_files)]

    @staticmethod
    def _fill_series(row: SeriesRow, position: int, rec: SeriesRecord) -> SeriesRow:
        row.position = position
        row.modality = rec.modality.value
        row.num_instances = rec.num_instances
        row.description = rec.description
        row.dir_name = rec.dir_name
        return row

    @staticmethod
    def _fill_nifti(row: NiftiRow, position: int, rec: NiftiRecord) -> NiftiRow:
        row.series_id = rec.series_id
        row.position = position
        row.modality = rec.modality.value
        row.shape = rec.shape
        row.voxel_spacing = rec.voxel_spacing
        row.file_name = rec.file_name
        return row

    def add_mask_version(self, study_id: str, version: MaskVersionRecord) -> None:
        with self.db.session() as session:
            session.add(
                MaskVersionRow(
                    id=version.version_id,
                    study_id=study_id,
                    source=version.source,
                    base_version_id=version.base_version_id,
                    labels=version.labels,
                    volume_ml=version.volume_ml,
                    model_name=version.model_name,
                    model_note=version.model_note,
                    file_name=version.file_name,
                    read_only=version.read_only,
                    edited_slices=version.edited_slices,
                    refined_slices=version.refined_slices,
                    created_by=version.created_by,
                    created_at=_naive(version.created_at),
                )
            )

    def _with_slices(self, study: StudyRecord) -> StudyRecord:
        for version in study.mask_versions:
            path = self.segmentation_dir(study.study_id) / version.file_name
            if path.is_file():
                version.slices_with_mask = list(_mask_slices(str(path)))
        return study

    def get(self, study_id: str, user_id: str | None = None) -> StudyRecord:
        """`user_id=None` is for internal callers (background jobs); requests always pass the caller."""
        self._study_dir(study_id)
        with self.db.session() as session:
            row = session.get(StudyRow, study_id)
            if row is None or (user_id is not None and row.user_id != user_id):
                raise errors.study_not_found()
            return self._with_slices(_study_record(row))

    def list_for_user(self, user_id: str) -> list[StudyRecord]:
        with self.db.session() as session:
            rows = session.scalars(
                select(StudyRow).where(StudyRow.user_id == user_id).order_by(StudyRow.created_at.desc())
            )
            return [self._with_slices(_study_record(r)) for r in rows]

    def count_for_user(self, user_id: str) -> int:
        with self.db.session() as session:
            return session.scalar(select(func.count()).select_from(StudyRow).where(StudyRow.user_id == user_id)) or 0

    def delete(self, study_id: str, user_id: str | None = None) -> None:
        study_dir = self._study_dir(study_id)
        with self.db.session() as session:
            row = session.get(StudyRow, study_id)
            if row is None or (user_id is not None and row.user_id != user_id):
                raise errors.study_not_found()
            session.delete(row)  # cascades to series, files, mask versions and jobs
        shutil.rmtree(study_dir, ignore_errors=True)

    def find_nifti(self, resource_id: str, user_id: str) -> tuple[StudyRecord, NiftiRecord, Path]:
        """Resolve an opaque NIfTI resource ID to its file."""
        with self.db.session() as session:
            row = session.get(NiftiRow, resource_id)
            if row is None or row.study.user_id != user_id:
                raise errors.resource_not_found()
            study, nifti = _study_record(row.study), _nifti_record(row)
        path = self.nifti_dir(study.study_id) / nifti.file_name
        if not path.is_file():
            raise errors.resource_not_found()
        return study, nifti, path

    def find_mask(self, version_id: str, user_id: str) -> Path:
        """Resolve an opaque mask version ID to its file."""
        with self.db.session() as session:
            row = session.get(MaskVersionRow, version_id)
            if row is None or row.study.user_id != user_id:
                raise errors.resource_not_found()
            study_id, file_name = row.study_id, row.file_name
        path = self.segmentation_dir(study_id) / file_name
        if not path.is_file():
            raise errors.resource_not_found()
        return path

    # -- cleanup ---------------------------------------------------------------

    def cleanup_expired(self) -> int:
        """Delete studies not touched within the TTL, and directories with no database row."""
        cutoff = utc_now() - self.ttl
        with self.db.session() as session:
            active_job = exists().where(JobRow.study_id == StudyRow.id, JobRow.status.in_(ACTIVE_JOB_STATUSES))
            expired = list(session.scalars(select(StudyRow).where(StudyRow.updated_at < cutoff, ~active_job)))
            expired_ids = [row.id for row in expired]
            for row in expired:
                session.delete(row)
            known = set(session.scalars(select(StudyRow.id)))

        removed = len(expired_ids)
        for study_id in expired_ids:
            shutil.rmtree(self.root / study_id, ignore_errors=True)
        for study_dir in self.root.iterdir():
            if study_dir.is_dir() and study_dir.name not in known:
                if datetime.fromtimestamp(study_dir.stat().st_mtime, timezone.utc).replace(tzinfo=None) < cutoff:
                    shutil.rmtree(study_dir, ignore_errors=True)
                    removed += 1
        if removed:
            logger.info("Removed %d expired studies", removed)
        return removed
