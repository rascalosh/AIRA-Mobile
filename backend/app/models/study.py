"""Internal study state persisted as JSON next to the study's temporary files.

These models may reference server-side locations by *relative* names only and are never
returned to the client directly — see `schemas.py` for the public API contract.
"""

from datetime import datetime, timezone
from enum import Enum

from pydantic import BaseModel, Field


class StudyStatus(str, Enum):
    UPLOADED = "uploaded"
    CONVERTING = "converting"
    CONVERTED = "converted"
    FAILED = "failed"


class Modality(str, Enum):
    T2W = "T2W"
    DWI = "DWI"
    ADC = "ADC"
    UNKNOWN = "unknown"


class SeriesRecord(BaseModel):
    series_id: str
    modality: Modality
    num_instances: int
    description: str | None = None
    # Directory name (relative to the study's dicom dir) holding this series' files.
    dir_name: str


class NiftiRecord(BaseModel):
    resource_id: str
    series_id: str
    modality: Modality
    shape: list[int]
    voxel_spacing: list[float]
    # File name relative to the study's nifti dir.
    file_name: str


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class StudyRecord(BaseModel):
    study_id: str
    status: StudyStatus = StudyStatus.UPLOADED
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)
    series: list[SeriesRecord] = []
    nifti_files: list[NiftiRecord] = []
    skipped_files: int = 0

    @property
    def modalities(self) -> list[Modality]:
        seen: list[Modality] = []
        for s in self.series:
            if s.modality != Modality.UNKNOWN and s.modality not in seen:
                seen.append(s.modality)
        return seen

    def touch(self) -> None:
        self.updated_at = _utcnow()
