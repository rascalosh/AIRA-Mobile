"""Temporary per-study storage.

Layout::

    {storage_dir}/{study_id}/
        study.json      # StudyRecord state
        upload/         # raw uploaded files (deleted after series grouping)
        dicom/{n}/      # valid DICOM files, one directory per series
        nifti/          # converted .nii.gz files
"""

import logging
import shutil
import threading
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.core import errors
from app.models.study import NiftiRecord, StudyRecord

logger = logging.getLogger(__name__)

_STATE_FILE = "study.json"


def new_id() -> str:
    return uuid.uuid4().hex


class StudyStorage:
    def __init__(self, root: Path, ttl_hours: int) -> None:
        self.root = root
        self.ttl = timedelta(hours=ttl_hours)
        self._lock = threading.Lock()
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

    # -- lifecycle -------------------------------------------------------------

    def create(self) -> StudyRecord:
        study = StudyRecord(study_id=new_id())
        for d in (self.upload_dir(study.study_id), self.dicom_dir(study.study_id), self.nifti_dir(study.study_id)):
            d.mkdir(parents=True, exist_ok=True)
        self.save(study)
        return study

    def save(self, study: StudyRecord) -> None:
        study.touch()
        path = self._study_dir(study.study_id) / _STATE_FILE
        tmp = path.with_suffix(".tmp")
        with self._lock:
            tmp.write_text(study.model_dump_json(), encoding="utf-8")
            tmp.replace(path)

    def get(self, study_id: str) -> StudyRecord:
        path = self._study_dir(study_id) / _STATE_FILE
        if not path.is_file():
            raise errors.study_not_found()
        with self._lock:
            return StudyRecord.model_validate_json(path.read_text(encoding="utf-8"))

    def delete(self, study_id: str) -> None:
        study_dir = self._study_dir(study_id)
        if not study_dir.is_dir():
            raise errors.study_not_found()
        shutil.rmtree(study_dir, ignore_errors=True)

    def find_nifti(self, resource_id: str) -> tuple[StudyRecord, NiftiRecord, Path]:
        """Resolve an opaque NIfTI resource ID to its file."""
        for state in self.root.glob(f"*/{_STATE_FILE}"):
            try:
                study = self.get(state.parent.name)
            except errors.AppError:
                continue
            for nifti in study.nifti_files:
                if nifti.resource_id == resource_id:
                    path = self.nifti_dir(study.study_id) / nifti.file_name
                    if path.is_file():
                        return study, nifti, path
        raise errors.resource_not_found()

    def cleanup_expired(self) -> int:
        """Delete studies older than the TTL. Returns the number removed."""
        cutoff = datetime.now(timezone.utc) - self.ttl
        removed = 0
        for study_dir in self.root.iterdir():
            if not study_dir.is_dir():
                continue
            state = study_dir / _STATE_FILE
            try:
                expired = StudyRecord.model_validate_json(state.read_text(encoding="utf-8")).updated_at < cutoff
            except (OSError, ValueError):
                # Orphaned or corrupt directory: fall back to its modification time.
                mtime = datetime.fromtimestamp(study_dir.stat().st_mtime, timezone.utc)
                expired = mtime < cutoff
            if expired:
                shutil.rmtree(study_dir, ignore_errors=True)
                removed += 1
        if removed:
            logger.info("Removed %d expired studies", removed)
        return removed
