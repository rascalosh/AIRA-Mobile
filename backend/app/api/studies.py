import shutil
from typing import Annotated

from fastapi import APIRouter, Depends, File, Response, UploadFile, status
from fastapi.concurrency import run_in_threadpool

from app.api.deps import get_app_settings, get_storage
from app.core import errors
from app.core.config import Settings
from app.models.schemas import (
    ConvertResponse,
    ErrorResponse,
    StudyResponse,
    StudyUploadResponse,
    nifti_files,
    series_infos,
    to_study_response,
)
from app.models.study import StudyStatus
from app.services import dicom_service, nifti_service, slice_service
from app.services.storage import StudyStorage

router = APIRouter(prefix="/api/v1/studies", tags=["studies"])

StorageDep = Annotated[StudyStorage, Depends(get_storage)]
SettingsDep = Annotated[Settings, Depends(get_app_settings)]

_errors = {r: {"model": ErrorResponse} for r in (400, 404, 409, 413, 422)}

# Studies currently being converted in this process.
_converting: set[str] = set()


@router.post("/upload", response_model=StudyUploadResponse, status_code=status.HTTP_201_CREATED, responses=_errors)
async def upload_study(
    files: Annotated[
        list[UploadFile],
        File(description="DICOM files of one study, one or more .zip archives, or a mix of both"),
    ],
    storage: StorageDep,
    settings: SettingsDep,
) -> StudyUploadResponse:
    study = storage.create()
    upload_dir = storage.upload_dir(study.study_id)
    try:
        saved = await dicom_service.save_uploads(files, upload_dir, settings.max_upload_bytes)
        saved = await run_in_threadpool(
            dicom_service.expand_archives, saved, upload_dir, settings.max_upload_bytes
        )
        study = await run_in_threadpool(dicom_service.group_into_series, study, saved, storage)
    except Exception:
        storage.delete(study.study_id)
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
async def convert_study(study_id: str, storage: StorageDep, settings: SettingsDep) -> ConvertResponse:
    study = storage.get(study_id)
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


@router.get("/{study_id}", response_model=StudyResponse, responses=_errors)
async def get_study(study_id: str, storage: StorageDep) -> StudyResponse:
    return to_study_response(storage.get(study_id))


@router.delete("/{study_id}", status_code=status.HTTP_204_NO_CONTENT, responses=_errors)
async def delete_study(study_id: str, storage: StorageDep) -> Response:
    if study_id in _converting:
        raise errors.invalid_state("The study cannot be deleted while it is being converted.")
    study = storage.get(study_id)
    for nifti in study.nifti_files:
        slice_service.discard_cache(nifti.resource_id)
    storage.delete(study_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
