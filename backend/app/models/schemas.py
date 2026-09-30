"""Public API contract (spec §9). Contains opaque IDs only — never filesystem paths."""

from datetime import datetime

from pydantic import BaseModel

from app.models.study import Modality, StudyRecord, StudyStatus


class HealthResponse(BaseModel):
    status: str


class SeriesInfo(BaseModel):
    series_id: str
    modality: Modality
    num_instances: int
    description: str | None = None


class NiftiFile(BaseModel):
    modality: Modality
    series_id: str
    resource_id: str
    shape: list[int]
    voxel_spacing: list[float]


class StudyUploadResponse(BaseModel):
    study_id: str
    status: StudyStatus
    modalities: list[Modality]
    series: list[SeriesInfo]
    skipped_files: int


class ConvertResponse(BaseModel):
    study_id: str
    status: StudyStatus
    nifti_files: list[NiftiFile]


class StudyResponse(BaseModel):
    study_id: str
    status: StudyStatus
    created_at: datetime
    modalities: list[Modality]
    series: list[SeriesInfo]
    nifti_files: list[NiftiFile]


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    error: ErrorDetail


def series_infos(study: StudyRecord) -> list[SeriesInfo]:
    return [
        SeriesInfo(
            series_id=s.series_id,
            modality=s.modality,
            num_instances=s.num_instances,
            description=s.description,
        )
        for s in study.series
    ]


def nifti_files(study: StudyRecord) -> list[NiftiFile]:
    return [
        NiftiFile(
            modality=n.modality,
            series_id=n.series_id,
            resource_id=n.resource_id,
            shape=n.shape,
            voxel_spacing=n.voxel_spacing,
        )
        for n in study.nifti_files
    ]


def to_study_response(study: StudyRecord) -> StudyResponse:
    return StudyResponse(
        study_id=study.study_id,
        status=study.status,
        created_at=study.created_at,
        modalities=study.modalities,
        series=series_infos(study),
        nifti_files=nifti_files(study),
    )
