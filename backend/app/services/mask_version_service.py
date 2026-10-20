"""Mask versions: save a corrected mask as a new version, and compare two versions.

The AI mask (`source="ai"`) is never written. A correction is always a *new* NIfTI file, made from a copy of the
base version with the edited slices replaced, saved with the base's affine and header. A save must name the study's
latest version as its base, otherwise it is a 409: the client reloads instead of overwriting newer edits.
"""

import threading

import nibabel as nib
import numpy as np

from app.core import errors
from app.models.study import MaskVersionRecord, StudyRecord
from app.services.storage import StudyStorage, new_id

_locks: dict[str, threading.Lock] = {}
_locks_guard = threading.Lock()


def _lock_for(study_id: str) -> threading.Lock:
    # ponytail: in-process only (the API runs as one process); use a database lock before scaling out.
    with _locks_guard:
        return _locks.setdefault(study_id, threading.Lock())


def version_of(study: StudyRecord, version_id: str) -> MaskVersionRecord:
    version = next((v for v in study.mask_versions if v.version_id == version_id), None)
    if version is None:
        raise errors.resource_not_found()
    return version


def _voxel_ml(image: nib.Nifti1Image) -> float:
    return float(np.prod(image.header.get_zooms()[:3])) / 1000


def create_version(
    storage: StudyStorage,
    study_id: str,
    user_id: str,
    base_version_id: str,
    slices: dict[int, np.ndarray],
    refined: list[int],
) -> MaskVersionRecord:
    """Save `slices` ({z: plane in array orientation, uint8}) on top of `base_version_id` as a new version."""
    with _lock_for(study_id):
        study = storage.get(study_id, user_id)
        base = version_of(study, base_version_id)
        latest = study.latest_mask
        if latest is None or latest.version_id != base.version_id:
            raise errors.version_conflict()

        path = storage.segmentation_dir(study_id) / base.file_name
        image = nib.load(str(path))
        data = np.array(image.dataobj, dtype=np.uint8)  # a copy: the base file is never modified
        allowed = {0} | {int(k) for k in base.labels}

        edited: list[int] = []
        for z, plane in sorted(slices.items()):
            if not 0 <= z < data.shape[2]:
                raise errors.invalid_mask_slice(f"Slice {z + 1} is outside this volume.")
            if plane.shape != data.shape[:2]:
                raise errors.invalid_mask_slice(f"Slice {z + 1} has the wrong size for this study.")
            if not set(np.unique(plane).tolist()) <= allowed:
                raise errors.invalid_mask_slice(f"Slice {z + 1} contains an unknown label.")
            if not np.array_equal(plane, data[:, :, z]):
                data[:, :, z] = plane
                edited.append(z)
        if not edited:
            raise errors.invalid_mask_slice("There are no changes to save.")

        version_id = new_id()
        file_name = f"{version_id}.nii.gz"
        out = nib.Nifti1Image(data, image.affine, image.header)
        out.set_data_dtype(np.uint8)
        nib.save(out, str(path.parent / file_name))

        record = MaskVersionRecord(
            version_id=version_id,
            source="manual_correction",
            base_version_id=base.version_id,
            labels=base.labels,
            volume_ml=round(float((data > 0).sum()) * _voxel_ml(image), 2),
            model_name=base.model_name,
            model_note=base.model_note,
            file_name=file_name,
            read_only=False,
            edited_slices=edited,
            refined_slices=sorted(set(refined) & set(edited)),
            created_by=user_id,
        )
        storage.add_mask_version(study_id, record)
        return record


def compare(storage: StudyStorage, study: StudyRecord, a_id: str, b_id: str) -> dict:
    """Overlap and volume difference between two versions of one study (any non-zero label counts as mask)."""
    a_rec, b_rec = version_of(study, a_id), version_of(study, b_id)
    seg_dir = storage.segmentation_dir(study.study_id)
    a_img, b_img = nib.load(str(seg_dir / a_rec.file_name)), nib.load(str(seg_dir / b_rec.file_name))
    a, b = np.asarray(a_img.dataobj) > 0, np.asarray(b_img.dataobj) > 0
    if a.shape != b.shape:
        raise errors.invalid_mask_slice("These versions cannot be compared.")

    inter, na, nb = int((a & b).sum()), int(a.sum()), int(b.sum())
    union = na + nb - inter
    voxel_ml = _voxel_ml(a_img)
    return {
        "a": a_id,
        "b": b_id,
        # Two empty masks agree perfectly.
        "dice": 1.0 if na + nb == 0 else 2 * inter / (na + nb),
        "iou": 1.0 if union == 0 else inter / union,
        "volume_ml_a": round(na * voxel_ml, 2),
        "volume_ml_b": round(nb * voxel_ml, 2),
        "changed_voxels": int((a ^ b).sum()),
    }
