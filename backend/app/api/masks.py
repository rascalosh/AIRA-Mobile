"""Mask editing endpoints: label slices, saving corrected versions, refinement proposals, comparison."""

import asyncio
import base64
import re
import time
from typing import Annotated

import numpy as np
from fastapi import APIRouter, Depends, File, Form, Query, Response, UploadFile, status
from fastapi.concurrency import run_in_threadpool

from app.api.deps import CurrentUser, get_app_settings, get_storage, limit_user
from app.core import errors
from app.core.config import Settings
from app.models.schemas import (
    CompareResponse,
    ErrorResponse,
    MaskVersionInfo,
    RefineResponse,
    mask_version_info,
)
from app.models.study import Modality
from app.services import mask_version_service, refine_service, slice_service
from app.services.storage import StudyStorage

router = APIRouter(prefix="/api/v1", tags=["masks"])

StorageDep = Annotated[StudyStorage, Depends(get_storage)]
SettingsDep = Annotated[Settings, Depends(get_app_settings)]

_errors = {r: {"model": ErrorResponse} for r in (400, 401, 404, 409, 422, 504)}
_MAX_SLICES = 64
_MAX_PNG_BYTES = 2 * 1024 * 1024
_SLICE_NAME = re.compile(r"^slice_(\d{1,4})\.png$")


async def _read_png(upload: UploadFile) -> np.ndarray:
    data = await upload.read(_MAX_PNG_BYTES + 1)
    await upload.close()
    if len(data) > _MAX_PNG_BYTES:
        raise errors.invalid_mask_slice("A mask slice is too large.")
    return await run_in_threadpool(slice_service.decode_label_png, data)


def _parse_slices(csv: str) -> list[int]:
    try:
        return [int(v) for v in csv.split(",") if v.strip()]
    except ValueError as exc:
        raise errors.invalid_mask_slice("refined_slices must be a comma-separated list of slice numbers.") from exc


@router.get(
    "/masks/{version_id}/slices/{z}",
    response_class=Response,
    responses={200: {"content": {"image/png": {}}}, 400: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
)
async def get_label_slice(version_id: str, z: int, user_id: CurrentUser, storage: StorageDep) -> Response:
    """One mask slice as a lossless 8-bit label PNG at native size, aligned with `GET .../slices/{z}?full=true`."""
    path = await run_in_threadpool(storage.find_mask, version_id, user_id)
    png = await run_in_threadpool(slice_service.render_label_png, path, z)
    return Response(content=png, media_type="image/png")


@router.post(
    "/studies/{study_id}/mask/versions",
    response_model=MaskVersionInfo,
    status_code=status.HTTP_201_CREATED,
    responses=_errors,
    dependencies=[limit_user("edit")],
)
async def save_mask_version(
    study_id: str,
    user_id: CurrentUser,
    storage: StorageDep,
    base_version_id: Annotated[str, Form()],
    slices: Annotated[list[UploadFile], File(description="One label PNG per edited slice, named slice_008.png")],
    refined_slices: Annotated[str, Form(description="Comma-separated slices where an accepted refinement was used")] = "",
) -> MaskVersionInfo:
    """Save edited slices as a new version. 409 when `base_version_id` is no longer the latest version."""
    storage.get(study_id, user_id)  # 404 for someone else's study before reading any upload
    if not 0 < len(slices) <= _MAX_SLICES:
        raise errors.invalid_mask_slice(f"Send between 1 and {_MAX_SLICES} slices.")

    planes: dict[int, np.ndarray] = {}
    for upload in slices:
        match = _SLICE_NAME.match(upload.filename or "")
        if match is None or int(match.group(1)) in planes:
            raise errors.invalid_mask_slice("Mask slices must be named slice_<number>.png, once each.")
        planes[int(match.group(1))] = slice_service.image_to_plane(await _read_png(upload))

    record = await run_in_threadpool(
        mask_version_service.create_version,
        storage,
        study_id,
        user_id,
        base_version_id,
        planes,
        _parse_slices(refined_slices),
    )
    study = storage.get(study_id, user_id)  # re-read so derived fields (slices_with_mask) are filled in
    return mask_version_info(study, mask_version_service.version_of(study, record.version_id))


@router.post(
    "/studies/{study_id}/mask/refine",
    response_model=RefineResponse,
    responses=_errors,
    dependencies=[limit_user("edit")],
)
async def refine_mask_slice(
    study_id: str,
    user_id: CurrentUser,
    storage: StorageDep,
    settings: SettingsDep,
    base_version_id: Annotated[str, Form()],
    slice_index: Annotated[int, Form(ge=0)],
    edited_slice: Annotated[UploadFile, File(description="The user's current label slice as a PNG")],
    label: Annotated[int, Form()] = 1,
    band_width_vox: Annotated[int, Form(ge=1, le=8)] = 3,
    method: Annotated[str, Form()] = "random_walker",
) -> RefineResponse:
    """A refinement *proposal* for one edited slice. Stateless: nothing is stored until the user saves."""
    if method not in settings.refine_enabled_methods:
        raise errors.invalid_mask_slice(f"The refinement method '{method}' is not available.")
    study = storage.get(study_id, user_id)
    base = mask_version_service.version_of(study, base_version_id)
    if str(label) not in base.labels:
        raise errors.invalid_mask_slice("Unknown label.")
    t2w = next((n for n in study.nifti_files if n.modality == Modality.T2W), None)
    if t2w is None:
        raise errors.refine_failed()

    base_png = await run_in_threadpool(
        slice_service.render_label_png, storage.segmentation_dir(study_id) / base.file_name, slice_index
    )
    base_img = slice_service.decode_label_png(base_png)
    edited = await _read_png(edited_slice)
    if edited.shape != base_img.shape:
        raise errors.invalid_mask_slice("The slice has the wrong size for this study.")
    image = await run_in_threadpool(
        slice_service.image_plane, t2w.resource_id, storage.nifti_dir(study_id) / t2w.file_name, slice_index
    )
    # The AI mask is never refined: only the user's own annotation is.
    ai = study.ai_mask
    protected = None
    if ai is not None:
        ai_png = await run_in_threadpool(
            slice_service.render_label_png, storage.segmentation_dir(study_id) / ai.file_name, slice_index
        )
        protected = slice_service.decode_label_png(ai_png) == label

    started = time.perf_counter()
    params = refine_service.RefineParams(band_width_vox=band_width_vox)
    try:
        proposed = await asyncio.wait_for(
            run_in_threadpool(refine_service.refine_slice, image, base_img, edited, label, params, protected),
            timeout=settings.refine_timeout_seconds,
        )
    except TimeoutError as exc:
        # ponytail: the worker thread finishes in the background; move refinement to a worker process if that matters.
        raise errors.refine_timeout() from exc
    except Exception as exc:
        raise errors.refine_failed() from exc

    return RefineResponse(
        slice_index=slice_index,
        method=method,
        band_width_vox=band_width_vox,
        proposed_slice_png_base64=base64.b64encode(slice_service.label_array_to_png(proposed)).decode(),
        changed_pixels=int((proposed != edited).sum()),
        runtime_ms=int((time.perf_counter() - started) * 1000),
    )


@router.get("/studies/{study_id}/mask/compare", response_model=CompareResponse, responses=_errors)
async def compare_mask_versions(
    study_id: str,
    user_id: CurrentUser,
    storage: StorageDep,
    a: Annotated[str, Query()],
    b: Annotated[str, Query()],
) -> CompareResponse:
    study = storage.get(study_id, user_id)
    return CompareResponse(**await run_in_threadpool(mask_version_service.compare, storage, study, a, b))
