"""Public API contract (spec §9). Contains opaque IDs only — never filesystem paths."""

from datetime import datetime

from pydantic import BaseModel

from app.models.job import JobRecord, JobStatus
from app.models.study import MaskVersionRecord, Modality, StudyRecord, StudyStatus


class HealthResponse(BaseModel):
    status: str


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    error: ErrorDetail


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


class SegmentationInfo(BaseModel):
    resource_id: str
    label: str
    volume_ml: float
    model_name: str
    model_note: str
    slices_with_mask: list[int] = []


class MaskVersionInfo(BaseModel):
    version_id: str
    name: str
    source: str
    base_version_id: str | None
    labels: dict[str, str]
    volume_ml: float
    read_only: bool
    edited_slices: list[int]
    refined_slices: list[int]
    slices_with_mask: list[int]
    created_at: datetime


class RefineResponse(BaseModel):
    slice_index: int
    method: str
    band_width_vox: int
    proposed_slice_png_base64: str
    changed_pixels: int
    runtime_ms: int


class CompareResponse(BaseModel):
    a: str
    b: str
    dice: float
    iou: float
    volume_ml_a: float
    volume_ml_b: float
    changed_voxels: int


class MaskVersionsResponse(BaseModel):
    study_id: str
    versions: list[MaskVersionInfo]


class JobResponse(BaseModel):
    job_id: str
    study_id: str
    kind: str
    status: JobStatus
    error: ErrorDetail | None = None
    created_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    # Set once the job has completed.
    segmentation: SegmentationInfo | None = None


class UserResponse(BaseModel):
    user_id: str
    token: str


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
    segmentation: SegmentationInfo | None = None
    latest_mask_version_id: str | None = None


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


def _segmentation_info(version: MaskVersionRecord) -> SegmentationInfo:
    return SegmentationInfo(
        resource_id=version.version_id,
        label=next(iter(version.labels.values()), "Segmentation"),
        volume_ml=version.volume_ml,
        model_name=version.model_name or "",
        model_note=version.model_note or "",
        slices_with_mask=version.slices_with_mask,
    )


def segmentation_info(study: StudyRecord) -> SegmentationInfo | None:
    """The AI mask version, which is what the app shows as the segmentation result."""
    ai = study.ai_mask
    return _segmentation_info(ai) if ai else None


def mask_version_info(study: StudyRecord, v: MaskVersionRecord) -> MaskVersionInfo:
    return MaskVersionInfo(
        version_id=v.version_id,
        name=study.version_name(v),
        source=v.source,
        base_version_id=v.base_version_id,
        labels=v.labels,
        volume_ml=v.volume_ml,
        read_only=v.read_only,
        edited_slices=v.edited_slices,
        refined_slices=v.refined_slices,
        slices_with_mask=v.slices_with_mask,
        created_at=v.created_at,
    )


def mask_versions_response(study: StudyRecord) -> MaskVersionsResponse:
    return MaskVersionsResponse(
        study_id=study.study_id, versions=[mask_version_info(study, v) for v in study.mask_versions]
    )


def to_job_response(job: JobRecord, study: StudyRecord) -> JobResponse:
    version = next((v for v in study.mask_versions if v.version_id == job.mask_version_id), None)
    return JobResponse(
        job_id=job.job_id,
        study_id=job.study_id,
        kind=job.kind,
        status=job.status,
        error=ErrorDetail(code=job.error_code, message=job.error_message or "") if job.error_code else None,
        created_at=job.created_at,
        started_at=job.started_at,
        finished_at=job.finished_at,
        segmentation=_segmentation_info(version) if version and job.status == JobStatus.COMPLETED else None,
    )


def to_study_response(study: StudyRecord) -> StudyResponse:
    return StudyResponse(
        study_id=study.study_id,
        status=study.status,
        created_at=study.created_at,
        modalities=study.modalities,
        series=series_infos(study),
        nifti_files=nifti_files(study),
        segmentation=segmentation_info(study),
        latest_mask_version_id=study.latest_mask.version_id if study.latest_mask else None,
    )
