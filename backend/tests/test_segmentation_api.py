"""Segmentation job tests. Synthetic data only.

The end-to-end test runs the real bundled weights (skipped when they are absent) on random
images, so it checks plumbing (jobs, shapes, orientation round-trip, storage, overlay), not accuracy.
"""

import io
import time
from pathlib import Path

import nibabel as nib
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.core.config import Settings
from app.main import create_app
from tests.conftest import as_upload, make_series, register

WEIGHTS = Path(__file__).resolve().parents[1] / "models" / "prostate_segmentation.pth"
ALL_THREE = {"t2": "t2_tse_tra", "adc": "ep2d_diff_tra_ADC", "dwi": "ax dwi b1000"}


def _upload_convert(client, tmp_path, kinds):
    files = []
    for name, description in kinds.items():
        files += make_series(tmp_path / name, description=description, prefix=name)
    study_id = client.post("/api/v1/studies/upload", files=as_upload(files)).json()["study_id"]
    assert client.post(f"/api/v1/studies/{study_id}/convert").status_code == 200
    return study_id


def _wait(client, job_id, timeout=180):
    deadline = time.time() + timeout
    while time.time() < deadline:
        job = client.get(f"/api/v1/jobs/{job_id}").json()
        if job["status"] in ("completed", "failed"):
            return job
        time.sleep(0.2)
    raise AssertionError("job did not finish")


def test_segment_requires_all_three_sequences(client, tmp_path):
    study_id = _upload_convert(client, tmp_path, {"t2": "t2_tse_tra", "adc": "ep2d_diff_tra_ADC"})

    response = client.post(f"/api/v1/studies/{study_id}/segment")

    # Bad input fails fast, before any job is created.
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "MISSING_REQUIRED_MODALITY"
    assert "DWI" in response.json()["error"]["message"]


def test_missing_model_fails_the_job_with_a_clear_error(tmp_path):
    settings = Settings(storage_dir=tmp_path / "s", model_path=tmp_path / "none.pth", _env_file=None)
    with TestClient(create_app(settings)) as client:
        register(client)
        study_id = _upload_convert(client, tmp_path, ALL_THREE)

        accepted = client.post(f"/api/v1/studies/{study_id}/segment")
        assert accepted.status_code == 202
        job = _wait(client, accepted.json()["job_id"])

    assert job["status"] == "failed"
    assert job["error"]["code"] == "MODEL_UNAVAILABLE"
    assert job["segmentation"] is None


@pytest.mark.skipif(not WEIGHTS.is_file(), reason="model weights not present")
def test_segment_end_to_end_with_real_weights(client, settings, tmp_path):
    study_id = _upload_convert(client, tmp_path, ALL_THREE)

    accepted = client.post(f"/api/v1/studies/{study_id}/segment")
    assert accepted.status_code == 202, accepted.text
    # Asking again while it runs returns the same job instead of starting a second one.
    assert client.post(f"/api/v1/studies/{study_id}/segment").json()["job_id"] == accepted.json()["job_id"]

    job = _wait(client, accepted.json()["job_id"])
    assert job["status"] == "completed", job
    seg = job["segmentation"]
    assert seg["label"] == "Lesion" and seg["volume_ml"] >= 0 and "Not for clinical use" in seg["model_note"]

    # Recorded on the study as the read-only AI mask version.
    study = client.get(f"/api/v1/studies/{study_id}").json()
    assert study["segmentation"]["resource_id"] == seg["resource_id"]
    [version] = client.get(f"/api/v1/studies/{study_id}/mask/versions").json()["versions"]
    assert version["version_id"] == seg["resource_id"] and version["source"] == "ai" and version["read_only"]

    # Asking again reuses the result.
    again = client.post(f"/api/v1/studies/{study_id}/segment").json()
    assert again["status"] == "completed" and again["segmentation"]["resource_id"] == seg["resource_id"]

    # The mask lives on the T2W grid, so the overlay lines up with the T2W slice PNG.
    mask = nib.load(settings.storage_dir / study_id / "segmentation" / f"{seg['resource_id']}.nii.gz")
    t2 = next(n for n in study["nifti_files"] if n["modality"] == "T2W")
    assert list(mask.shape) == t2["shape"]

    overlay = client.get(f"/api/v1/resources/{seg['resource_id']}/overlay/0")
    assert overlay.status_code == 200 and overlay.headers["content-type"] == "image/png"
    image = Image.open(io.BytesIO(overlay.content))
    slice_png = Image.open(io.BytesIO(client.get(f"/api/v1/resources/{t2['resource_id']}/slices/0").content))
    assert image.mode == "RGBA" and image.size == slice_png.size
    assert client.get(f"/api/v1/resources/{seg['resource_id']}/overlay/999").status_code == 400


def test_study_reports_which_slices_contain_mask(client, settings, t2w_series):
    """Known mask slices come back on the study, the list and the mask versions' study; empty masks give []."""
    from app.models.study import MaskVersionRecord
    from app.services.storage import new_id

    study_id = client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).json()["study_id"]
    client.post(f"/api/v1/studies/{study_id}/convert")
    shape = client.get(f"/api/v1/studies/{study_id}").json()["nifti_files"][0]["shape"]

    import numpy as np

    mask = np.zeros(shape, dtype=np.uint8)
    mask[3:6, 3:6, 2] = 1
    mask[4, 4, 5] = 1
    version_id = new_id()
    out_dir = settings.storage_dir / study_id / "segmentation"
    out_dir.mkdir(parents=True, exist_ok=True)
    nib.save(nib.Nifti1Image(mask, np.eye(4)), str(out_dir / f"{version_id}.nii.gz"))
    client.app.state.storage.add_mask_version(
        study_id,
        MaskVersionRecord(
            version_id=version_id, labels={"1": "Lesion"}, volume_ml=0.1, file_name=f"{version_id}.nii.gz"
        ),
    )

    study = client.get(f"/api/v1/studies/{study_id}").json()
    assert study["segmentation"]["slices_with_mask"] == [2, 5]
    assert client.get("/api/v1/studies").json()[0]["segmentation"]["slices_with_mask"] == [2, 5]
