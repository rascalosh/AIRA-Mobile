"""Segmentation orchestration: feed a converted study to the ML client and record the result as the AI mask version."""

import logging

import nibabel as nib
import numpy as np

from app.clients.ml_model_client import MLModelClient, ModelInput
from app.core import errors
from app.core.config import Settings
from app.models.study import MaskVersionRecord, Modality, StudyRecord, StudyStatus
from app.services.storage import StudyStorage, new_id

logger = logging.getLogger(__name__)

# The bundled model takes all three sequences (T2W, ADC, DWI): unlike conversion, which only needs T2W.
REQUIRED = (Modality.T2W, Modality.ADC, Modality.DWI)


class SegmentationService:
    def __init__(self, client: MLModelClient, storage: StudyStorage, settings: Settings) -> None:
        self.client = client
        self.storage = storage
        self.settings = settings

    def check(self, study: StudyRecord) -> None:
        """Raise a user-facing error if the study cannot be segmented."""
        if study.status != StudyStatus.CONVERTED:
            raise errors.invalid_state("The study must be converted before it can be segmented.")
        have = {n.modality for n in study.nifti_files}
        missing = [m.value for m in REQUIRED if m not in have]
        if missing:
            raise errors.missing_required_modality(missing)

    async def run(self, study: StudyRecord, user_id: str | None = None) -> StudyRecord:
        """Run the model and store the result as the study's read-only AI mask version."""
        self.check(study)
        if study.ai_mask is not None:
            return study

        files = {n.modality: self.storage.nifti_dir(study.study_id) / n.file_name for n in study.nifti_files}
        out_dir = self.storage.segmentation_dir(study.study_id)
        try:
            out = await self.client.segment([ModelInput(m.value, files[m]) for m in REQUIRED], out_dir)
        except errors.AppError:
            raise
        except Exception as exc:
            # Exception text may include paths / header values: log only the type.
            logger.warning("Study %s: segmentation failed (%s)", study.study_id, type(exc).__name__)
            raise errors.segmentation_failed() from exc

        version_id = new_id()
        file_name = f"{version_id}.nii.gz"
        out.mask_path.replace(out_dir / file_name)

        img = nib.load(str(out_dir / file_name))
        voxel_ml = float(np.prod(img.header.get_zooms()[:3])) / 1000
        version = MaskVersionRecord(
            version_id=version_id,
            source="ai",
            labels={str(k): v for k, v in out.labels.items()},
            volume_ml=round(float(np.asarray(img.dataobj).sum()) * voxel_ml, 2),
            model_name=self.settings.model_name,
            model_note=self.settings.model_note,
            file_name=file_name,
            read_only=True,
            created_by=user_id,
        )
        self.storage.add_mask_version(study.study_id, version)
        study.mask_versions.append(version)
        return study
