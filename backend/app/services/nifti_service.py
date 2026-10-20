"""DICOM → NIfTI conversion using dicom2nifti (spec §5: no custom converter), and direct NIfTI import."""

import logging
import re
from pathlib import Path

import dicom2nifti
import nibabel as nib
import numpy as np

from app.core import errors
from app.core.config import Settings
from app.models.study import Modality, NiftiRecord, SeriesRecord, StudyRecord, StudyStatus
from app.services.storage import StudyStorage, new_id

logger = logging.getLogger(__name__)

# dicom2nifti logs file paths and header details; keep it quiet.
logging.getLogger("dicom2nifti").setLevel(logging.ERROR)


def _convert_series(study: StudyRecord, series: SeriesRecord, storage: StudyStorage, max_voxels: int) -> NiftiRecord:
    resource_id = new_id()
    file_name = f"{resource_id}.nii.gz"
    source = storage.dicom_dir(study.study_id) / series.dir_name
    target = storage.nifti_dir(study.study_id) / file_name

    dicom2nifti.dicom_series_to_nifti(str(source), str(target), reorient_nifti=True)

    header = nib.load(str(target)).header
    shape = [int(d) for d in header.get_data_shape()]
    if len(shape) not in (3, 4) or int(np.prod(shape)) > max_voxels:
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
            results.append(_convert_series(study, series, storage, settings.max_volume_voxels))
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


# -- direct NIfTI upload ------------------------------------------------------------

_SUFFIX_MODALITY = {"t2w": Modality.T2W, "t2": Modality.T2W, "adc": Modality.ADC, "hbv": Modality.DWI, "dwi": Modality.DWI}
# Masks, and `reshaped` copies: those are the network-grid images from the training notebook (placeholder spacing), not scans.
_NOT_IMAGES = {"mask", "seg", "segmentation", "label", "labels", "reshaped"}


def is_nifti(path: Path) -> bool:
    return path.name.lower().endswith((".nii", ".nii.gz"))


def modality_from_name(name: str) -> Modality:
    """`10008_1000008_t2w_preprocessed.nii.gz` -> T2W, `..._hbv.nii` -> DWI. Masks and unknown names give UNKNOWN.

    The modality is not stored in a NIfTI file, so the name decides. The last recognised token wins,
    which handles suffixes such as `_preprocessed` and names like `dwi(hbv)`. Masks and `reshaped` files are skipped.
    """
    tokens = [t for t in re.split(r"[^a-z0-9]+", re.sub(r"\.nii(\.gz)?$", "", name.lower())) if t]
    if _NOT_IMAGES & set(tokens):
        return Modality.UNKNOWN
    return next((_SUFFIX_MODALITY[t] for t in reversed(tokens) if t in _SUFFIX_MODALITY), Modality.UNKNOWN)


def import_study(study: StudyRecord, paths: list[Path], storage: StudyStorage, settings: Settings) -> StudyRecord:
    """Adopt uploaded NIfTI files as the study's volumes; the study comes out converted."""
    allowed = set(settings.allowed_modalities)
    volumes: dict[Modality, Path] = {}
    skipped = 0
    for path in paths:
        modality = modality_from_name(path.name) if is_nifti(path) else Modality.UNKNOWN
        if modality == Modality.UNKNOWN or modality.value not in allowed or modality in volumes:
            skipped += 1
            continue
        volumes[modality] = path

    missing = [m for m in settings.required_modalities if Modality(m) not in volumes]
    if missing:
        raise errors.missing_required_modality(missing)

    series: list[SeriesRecord] = []
    nifti_files: list[NiftiRecord] = []
    for modality, path in volumes.items():
        try:
            image = nib.load(str(path))
            shape = [int(d) for d in image.shape]
            # Checked against the header before any voxel is read, so a small file cannot expand without limit.
            if len(shape) not in (3, 4) or min(shape) < 1 or int(np.prod(shape)) > settings.max_volume_voxels:
                raise ValueError("unsupported NIfTI dimensions")
            spacing = [round(float(z), 6) for z in image.header.get_zooms()[:3]]
            resource_id, series_id = new_id(), new_id()
            file_name = f"{resource_id}.nii.gz"
            target = storage.nifti_dir(study.study_id) / file_name
            if path.name.lower().endswith(".nii.gz"):
                np.asanyarray(image.dataobj[..., :1] if len(shape) == 4 else image.dataobj[:, :, :1])  # readable?
                path.replace(target)
            else:
                nib.save(image, str(target))
        except Exception as exc:  # nibabel raises a variety of exception types for bad files
            logger.warning("Study %s: unreadable NIfTI for %s (%s)", study.study_id, modality.value, type(exc).__name__)
            raise errors.invalid_image() from exc
        series.append(SeriesRecord(series_id=series_id, modality=modality, num_instances=shape[2], dir_name=""))
        nifti_files.append(
            NiftiRecord(
                resource_id=resource_id,
                series_id=series_id,
                modality=modality,
                shape=shape,
                voxel_spacing=spacing,
                file_name=file_name,
            )
        )

    study.series, study.nifti_files, study.skipped_files = series, nifti_files, skipped
    study.status = StudyStatus.CONVERTED
    logger.info("Study %s: imported %d NIfTI volumes, %d files skipped", study.study_id, len(volumes), skipped)
    return study
