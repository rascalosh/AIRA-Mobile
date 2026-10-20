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


class MaskVersionRecord(BaseModel):
    """A segmentation mask version. The AI output (`source="ai"`) is read-only and never overwritten."""

    version_id: str
    source: str = "ai"  # "ai" | "manual_correction"
    base_version_id: str | None = None
    labels: dict[str, str]
    volume_ml: float
    model_name: str | None = None
    model_note: str | None = None
    # File name in the study's segmentation dir, on the T2W grid.
    file_name: str
    read_only: bool = True
    edited_slices: list[int] = []
    refined_slices: list[int] = []
    # Axial slices that contain mask (derived from the file, not stored in the database).
    slices_with_mask: list[int] = []
    created_by: str | None = None
    created_at: datetime = Field(default_factory=_utcnow)


class StudyRecord(BaseModel):
    study_id: str
    user_id: str = ""
    status: StudyStatus = StudyStatus.UPLOADED
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)
    series: list[SeriesRecord] = []
    nifti_files: list[NiftiRecord] = []
    skipped_files: int = 0
    mask_versions: list[MaskVersionRecord] = []

    @property
    def modalities(self) -> list[Modality]:
        seen: list[Modality] = []
        for s in self.series:
            if s.modality != Modality.UNKNOWN and s.modality not in seen:
                seen.append(s.modality)
        return seen

    @property
    def latest_mask(self) -> MaskVersionRecord | None:
        """The newest version: the only one a correction may be based on."""
        return self.mask_versions[-1] if self.mask_versions else None

    def version_name(self, version: MaskVersionRecord) -> str:
        """"AI", "Corrected v1", "Corrected v2", ... in creation order."""
        if version.source == "ai":
            return "AI"
        corrected = [v.version_id for v in self.mask_versions if v.source != "ai"]
        return f"Corrected v{corrected.index(version.version_id) + 1}"

    @property
    def ai_mask(self) -> MaskVersionRecord | None:
        return next((v for v in self.mask_versions if v.source == "ai"), None)

    def touch(self) -> None:
        self.updated_at = _utcnow()
