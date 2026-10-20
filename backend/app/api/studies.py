import shutil
from typing import Annotated

from fastapi import APIRouter, Depends, File, Response, UploadFile, status
from fastapi.concurrency import run_in_threadpool

from app.api.deps import CurrentUser, get_app_settings, get_jobs, get_storage, limit_user
from app.core import errors
from app.core.config import Settings
from app.models.schemas import (
    ConvertResponse,
    ErrorResponse,
    JobResponse,
    MaskVersionsResponse,
    StudyResponse,
    StudyUploadResponse,
    mask_versions_response,
    nifti_files,
    series_infos,
    to_job_response,
    to_study_response,
)
from app.models.study import StudyStatus
from app.services import dicom_service, nifti_service, slice_service
from app.services.jobs import JobService
from app.services.storage import StudyStorage

router = APIRouter(prefix="/api/v1/studies", tags=["studies"])

StorageDep = Annotated[StudyStorage, Depends(get_storage)]
SettingsDep = Annotated[Settings, Depends(get_app_settings)]
JobsDep = Annotated[JobService, Depends(get_jobs)]

_errors = {r: {"model": ErrorResponse} for r in (400, 401, 404, 409, 413, 422)}

# Studies currently being converted in this process.
_converting: set[str] = set()


@router.get("", response_model=list[StudyResponse], responses=_errors)
async def list_studies(user_id: CurrentUser, storage: StorageDep) -> list[StudyResponse]:
    """The caller's studies, newest first."""
    studies = await run_in_threadpool(storage.list_for_user, user_id)
    return [to_study_response(s) for s in studies]


@router.post(
    "/upload",
    response_model=StudyUploadResponse,
    status_code=status.HTTP_201_CREATED,
    responses=_errors,
    dependencies=[limit_user("upload")],
)
async def upload_study(
    files: Annotated[
        list[UploadFile],
        File(description="DICOM files of one study, one or more .zip archives, or a mix of both"),
    ],
    user_id: CurrentUser,
    storage: StorageDep,
    settings: SettingsDep,
) -> StudyUploadResponse:
    if len(files) > settings.max_upload_files:
        raise errors.quota_exceeded(f"Upload at most {settings.max_upload_files} files at once.")
    if await run_in_threadpool(storage.count_for_user, user_id) >= settings.max_studies_per_user:
        raise errors.quota_exceeded("You have reached the study limit. Delete a study to add another.")
    study = storage.create(user_id)
    upload_dir = storage.upload_dir(study.study_id)
    try:
        saved = await dicom_service.save_uploads(files, upload_dir, settings.max_upload_bytes)
        saved = await run_in_threadpool(
            dicom_service.expand_archives, saved, upload_dir, settings.max_upload_bytes, settings.max_zip_members
        )
        if any(nifti_service.is_nifti(p) for p in saved):
            # NIfTI files are already volumes: the study comes out converted, without the DICOM step.
            study = await run_in_threadpool(nifti_service.import_study, study, saved, storage, settings)
        else:
            study = await run_in_threadpool(dicom_service.group_into_series, study, saved, storage)
    except Exception:
        storage.delete(study.study_id, user_id)
        raise
    shutil.rmtree(upload_dir, ignore_errors=True)
    storage.save(study)

    return StudyUploadResponse(
        study_id=study.study_id,
        status=study.status,
        modalities=study.modalities,
        series=series_infos(study),
        skipped_files=study.skipped_files,
    )


@router.post("/{study_id}/convert", response_model=ConvertResponse, responses=_errors)
async def convert_study(
    study_id: str, user_id: CurrentUser, storage: StorageDep, settings: SettingsDep
) -> ConvertResponse:
    study = storage.get(study_id, user_id)
    if study.status == StudyStatus.CONVERTED:
        return ConvertResponse(study_id=study.study_id, status=study.status, nifti_files=nifti_files(study))
    if study.status == StudyStatus.CONVERTING or study_id in _converting:
        raise errors.invalid_state("The study is already being converted.")

    _converting.add(study_id)
    previous = study.status
    study.status = StudyStatus.CONVERTING
    storage.save(study)
    try:
        study = await run_in_threadpool(nifti_service.convert_study, study, storage, settings)
    except errors.AppError as exc:
        study.status = StudyStatus.FAILED if exc.code == "CONVERSION_FAILED" else previous
        storage.save(study)
        raise
    except Exception:
        study.status = StudyStatus.FAILED
        storage.save(study)
        raise
    finally:
        _converting.discard(study_id)
    storage.save(study)

    return ConvertResponse(study_id=study.study_id, status=study.status, nifti_files=nifti_files(study))


@router.post(
    "/{study_id}/segment",
    response_model=JobResponse,
    status_code=status.HTTP_202_ACCEPTED,
    responses=_errors,
    dependencies=[limit_user("segment")],
)
async def segment_study(study_id: str, user_id: CurrentUser, storage: StorageDep, jobs: JobsDep) -> JobResponse:
    """Queue the segmentation model. Poll `GET /api/v1/jobs/{job_id}` for the result."""
    study = storage.get(study_id, user_id)
    job = jobs.start_segmentation(study, user_id)
    return to_job_response(job, study)


@router.get("/{study_id}/mask/versions", response_model=MaskVersionsResponse, responses=_errors)
async def list_mask_versions(study_id: str, user_id: CurrentUser, storage: StorageDep) -> MaskVersionsResponse:
    return mask_versions_response(storage.get(study_id, user_id))


@router.get("/{study_id}", response_model=StudyResponse, responses=_errors)
async def get_study(study_id: str, user_id: CurrentUser, storage: StorageDep) -> StudyResponse:
    return to_study_response(storage.get(study_id, user_id))


@router.delete("/{study_id}", status_code=status.HTTP_204_NO_CONTENT, responses=_errors)
async def delete_study(study_id: str, user_id: CurrentUser, storage: StorageDep, jobs: JobsDep) -> Response:
    study = storage.get(study_id, user_id)
    if study_id in _converting or jobs.has_active(study_id):
        raise errors.invalid_state("The study cannot be deleted while it is being processed.")
    for nifti in study.nifti_files:
        slice_service.discard_cache(nifti.resource_id)
    storage.delete(study_id, user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
