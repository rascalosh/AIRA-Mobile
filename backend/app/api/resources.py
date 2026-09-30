from typing import Annotated

from fastapi import APIRouter, Depends, Response
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse

from app.api.deps import get_storage
from app.models.schemas import ErrorResponse
from app.services import slice_service
from app.services.storage import StudyStorage

router = APIRouter(prefix="/api/v1/resources", tags=["resources"])

StorageDep = Annotated[StudyStorage, Depends(get_storage)]


@router.get(
    "/{resource_id}",
    response_class=FileResponse,
    responses={200: {"content": {"application/gzip": {}}}, 404: {"model": ErrorResponse}},
)
async def download_resource(resource_id: str, storage: StorageDep) -> FileResponse:
    _, nifti, path = await run_in_threadpool(storage.find_nifti, resource_id)
    return FileResponse(
        path,
        media_type="application/gzip",
        filename=f"{nifti.modality.value.lower()}_{resource_id}.nii.gz",
    )


@router.get(
    "/{resource_id}/slices/{index}",
    response_class=Response,
    responses={
        200: {"content": {"image/png": {}}},
        400: {"model": ErrorResponse},
        404: {"model": ErrorResponse},
        422: {"model": ErrorResponse},
    },
)
async def get_slice(resource_id: str, index: int, storage: StorageDep) -> Response:
    """One slice of a converted NIfTI volume, rendered to a grayscale PNG.

    Slicing happens along axis 2 (axial, after dicom2nifti's reorientation).
    """
    _, _, path = await run_in_threadpool(storage.find_nifti, resource_id)
    png_bytes = await run_in_threadpool(slice_service.render_slice_png, resource_id, path, index)
    return Response(content=png_bytes, media_type="image/png")
