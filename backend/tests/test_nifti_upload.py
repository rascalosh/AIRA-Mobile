"""Uploading NIfTI files directly (no DICOM). Synthetic data only."""

import io
import time
import zipfile
from pathlib import Path

import nibabel as nib
import numpy as np
import pytest
from PIL import Image

from app.models.study import Modality
from app.services.nifti_service import modality_from_name

WEIGHTS = Path(__file__).resolve().parents[1] / "models" / "prostate_segmentation.pth"
LPS_AFFINE = np.diag([-0.5, -0.5, 3.0, 1.0])  # RAS affine of an LPS-indexed volume


def nifti_bytes(shape=(48, 48, 6), gz=True, seed=0, affine=LPS_AFFINE) -> bytes:
    data = np.random.default_rng(seed).integers(0, 1000, shape).astype(np.float32)
    path = Path(__import__("tempfile").mkdtemp()) / ("v.nii.gz" if gz else "v.nii")
    nib.save(nib.Nifti1Image(data, affine), str(path))
    return path.read_bytes()


def upload(client, named: dict[str, bytes]):
    files = [("files", (name, content, "application/octet-stream")) for name, content in named.items()]
    return client.post("/api/v1/studies/upload", files=files)


THREE = lambda: {  # noqa: E731
    "10008_1000008_t2w_preprocessed.nii.gz": nifti_bytes((64, 64, 6), seed=1),
    "10008_1000008_adc_preprocessed.nii.gz": nifti_bytes((24, 24, 6), seed=2),
    "10008_1000008_hbv_preprocessed.nii.gz": nifti_bytes((24, 24, 6), seed=3),
}


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("10008_1000008_t2w_preprocessed.nii.gz", Modality.T2W),
        ("case_ADC.NII.GZ", Modality.ADC),
        ("x_hbv.nii", Modality.DWI),
        ("dwi_hbv_.nii.gz", Modality.DWI),  # what "dwi(hbv)" becomes after sanitising
        ("t2w.nii.gz", Modality.T2W),
        ("10008_predicted_mask.nii.gz", Modality.UNKNOWN),
        ("10008_t2w_seg.nii.gz", Modality.UNKNOWN),
        ("10008_1000008_sag.nii.gz", Modality.UNKNOWN),
        ("10008_reshaped_t2w.nii.gz", Modality.UNKNOWN),  # the notebook's resized copy, not a scan
        ("brain.nii.gz", Modality.UNKNOWN),
    ],
)
def test_modality_comes_from_the_file_name(name, expected):
    assert modality_from_name(name) == expected


def test_three_nifti_files_make_a_converted_study(client):
    named = {**THREE(), "10008_predicted_mask.nii.gz": nifti_bytes()}

    response = upload(client, named)

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "converted"
    assert sorted(body["modalities"]) == ["ADC", "DWI", "T2W"]
    assert body["skipped_files"] == 1  # the mask

    study = client.get(f"/api/v1/studies/{body['study_id']}").json()
    shapes = {n["modality"]: n["shape"] for n in study["nifti_files"]}
    assert shapes == {"T2W": [64, 64, 6], "ADC": [24, 24, 6], "DWI": [24, 24, 6]}
    assert next(n for n in study["nifti_files"] if n["modality"] == "T2W")["voxel_spacing"] == [0.5, 0.5, 3.0]

    # The app's next step (convert) is a no-op, and slices render.
    converted = client.post(f"/api/v1/studies/{body['study_id']}/convert")
    assert converted.status_code == 200 and len(converted.json()["nifti_files"]) == 3
    slice_png = client.get(f"/api/v1/resources/{study['nifti_files'][0]['resource_id']}/slices/0")
    assert slice_png.status_code == 200
    Image.open(io.BytesIO(slice_png.content)).verify()


def test_reshaped_copies_are_ignored_in_favour_of_the_real_volumes(client):
    named = {
        "10008_reshaped_t2w.nii.gz": nifti_bytes((32, 32, 4), seed=7),  # comes first, must not win
        "10008_reshaped_adc.nii.gz": nifti_bytes((16, 16, 4), seed=8),
        **THREE(),
    }

    response = upload(client, named)

    assert response.status_code == 201
    assert response.json()["skipped_files"] == 2
    study = client.get(f"/api/v1/studies/{response.json()['study_id']}").json()
    assert next(n for n in study["nifti_files"] if n["modality"] == "T2W")["shape"] == [64, 64, 6]


def test_plain_nii_and_zip_uploads_work(client):
    plain = upload(client, {"a_t2w.nii": nifti_bytes(gz=False)})
    assert plain.status_code == 201 and plain.json()["modalities"] == ["T2W"]

    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as z:
        for name, content in THREE().items():
            z.writestr(f"study/{name}", content)
    zipped = client.post("/api/v1/studies/upload", files=[("files", ("study.zip", archive.getvalue(), "application/zip"))])
    assert zipped.status_code == 201 and sorted(zipped.json()["modalities"]) == ["ADC", "DWI", "T2W"]


def test_t2w_is_required(client):
    response = upload(client, {"a_adc.nii.gz": nifti_bytes(), "a_hbv.nii.gz": nifti_bytes()})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "MISSING_REQUIRED_MODALITY"


def test_unreadable_nifti_is_rejected_and_leaves_no_study(client):
    response = upload(client, {"a_t2w.nii.gz": b"this is not a nifti file"})

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_IMAGE"
    assert client.get("/api/v1/studies").json() == []


def test_two_files_for_one_modality_keep_the_first(client):
    response = upload(client, {"a_t2w.nii.gz": nifti_bytes(seed=1), "b_t2w.nii.gz": nifti_bytes(seed=2)})

    assert response.status_code == 201
    assert response.json()["skipped_files"] == 1


@pytest.mark.skipif(not WEIGHTS.is_file(), reason="model weights not present")
def test_nifti_study_can_be_segmented(client):
    study_id = upload(client, THREE()).json()["study_id"]

    job_id = client.post(f"/api/v1/studies/{study_id}/segment").json()["job_id"]
    deadline = time.time() + 180
    while (job := client.get(f"/api/v1/jobs/{job_id}").json())["status"] not in ("completed", "failed"):
        assert time.time() < deadline
        time.sleep(0.3)

    assert job["status"] == "completed", job
    assert job["segmentation"]["label"] == "Lesion"
