"""DICOM → NIfTI conversion using dicom2nifti (spec §5: no custom converter)."""

import logging

import dicom2nifti
import nibabel as nib

from app.core import errors
from app.core.config import Settings
from app.models.study import Modality, NiftiRecord, SeriesRecord, StudyRecord, StudyStatus
from app.services.storage import StudyStorage, new_id

logger = logging.getLogger(__name__)

# dicom2nifti logs file paths and header details; keep it quiet.
logging.getLogger("dicom2nifti").setLevel(logging.ERROR)


def _convert_series(study: StudyRecord, series: SeriesRecord, storage: StudyStorage) -> NiftiRecord:
    resource_id = new_id()
    file_name = f"{resource_id}.nii.gz"
    source = storage.dicom_dir(study.study_id) / series.dir_name
    target = storage.nifti_dir(study.study_id) / file_name

    dicom2nifti.dicom_series_to_nifti(str(source), str(target), reorient_nifti=True)

    header = nib.load(str(target)).header
    shape = [int(d) for d in header.get_data_shape()]
    if len(shape) not in (3, 4):
        target.unlink(missing_ok=True)
        raise ValueError("unexpected NIfTI dimensionality")
    spacing = [round(float(z), 6) for z in header.get_zooms()[:3]]

    return NiftiRecord(
        resource_id=resource_id,
        series_id=series.series_id,
        modality=series.modality,
        shape=shape,
        voxel_spacing=spacing,
        file_name=file_name,
    )


def convert_study(study: StudyRecord, storage: StudyStorage, settings: Settings) -> StudyRecord:
    """Convert all supported series of a study. Blocking: run in a worker thread."""
    allowed = {Modality(m) for m in settings.allowed_modalities}
    required = [Modality(m) for m in settings.required_modalities]

    candidates = [s for s in study.series if s.modality in allowed]
    if not candidates:
        raise errors.unsupported_modality()
    present = {s.modality for s in candidates}
    missing = [m.value for m in required if m not in present]
    if missing:
        raise errors.missing_required_modality(missing)

    results: list[NiftiRecord] = []
    failed: set[Modality] = set()
    for series in candidates:
        try:
            results.append(_convert_series(study, series, storage))
        except Exception as exc:  # dicom2nifti raises a variety of exception types
            # Exception text may include paths / header values: log only the type.
            logger.warning(
                "Study %s: conversion of a %s series failed (%s)",
                study.study_id,
                series.modality.value,
                type(exc).__name__,
            )
            failed.add(series.modality)

    converted = {r.modality for r in results}
    if not results or any(m in failed and m not in converted for m in required):
        for r in results:
            (storage.nifti_dir(study.study_id) / r.file_name).unlink(missing_ok=True)
        raise errors.conversion_failed()

    study.nifti_files = results
    study.status = StudyStatus.CONVERTED
    return study
