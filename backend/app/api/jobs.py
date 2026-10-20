from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import CurrentUser, get_jobs, get_storage
from app.models.schemas import ErrorResponse, JobResponse, to_job_response
from app.services.jobs import JobService
from app.services.storage import StudyStorage

router = APIRouter(prefix="/api/v1/jobs", tags=["jobs"])


@router.get("/{job_id}", response_model=JobResponse, responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}})
async def get_job(
    job_id: str,
    user_id: CurrentUser,
    jobs: Annotated[JobService, Depends(get_jobs)],
    storage: Annotated[StudyStorage, Depends(get_storage)],
) -> JobResponse:
    job = jobs.get(job_id, user_id)
    return to_job_response(job, storage.get(job.study_id))
