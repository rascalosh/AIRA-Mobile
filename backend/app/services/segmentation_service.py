"""Segmentation orchestration (Phase 3).

Will load a study's converted NIfTI files, call `MLModelClient.segment` and store the returned
mask as a result resource. Model preprocessing stays inside the ML service.
"""

from app.clients.ml_model_client import MLModelClient
from app.models.study import StudyRecord


class SegmentationService:
    def __init__(self, client: MLModelClient) -> None:
        self.client = client

    async def run(self, study: StudyRecord) -> str:
        raise NotImplementedError("Segmentation is implemented in Phase 3 (ML API integration).")
