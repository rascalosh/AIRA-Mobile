from pathlib import Path

import nibabel as nib

from tests.conftest import as_upload, make_series, zip_files


def _upload(client, paths):
    return client.post("/api/v1/studies/upload", files=as_upload(paths))


def test_upload_convert_download(client, t2w_series, tmp_path: Path):
    response = _upload(client, t2w_series)
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "uploaded"
    assert body["modalities"] == ["T2W"]
    assert body["series"][0]["num_instances"] == len(t2w_series)
    study_id = body["study_id"]

    response = client.post(f"/api/v1/studies/{study_id}/convert")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "converted"
    [nifti] = body["nifti_files"]
    assert nifti["modality"] == "T2W"
    assert sorted(nifti["shape"]) == [8, 32, 32]
    assert "path" not in str(body).lower()

    # Converting again is idempotent.
    again = client.post(f"/api/v1/studies/{study_id}/convert")
    assert again.json()["nifti_files"][0]["resource_id"] == nifti["resource_id"]

    download = client.get(f"/api/v1/resources/{nifti['resource_id']}")
    assert download.status_code == 200
    out = tmp_path / "out.nii.gz"
    out.write_bytes(download.content)
    assert sorted(nib.load(out).shape) == [8, 32, 32]

    study = client.get(f"/api/v1/studies/{study_id}").json()
    assert study["status"] == "converted"
    assert len(study["nifti_files"]) == 1


def test_upload_zip_with_multiple_series(client, tmp_path: Path):
    t2 = make_series(tmp_path / "a", description="t2_tse_tra", prefix="t2")
    adc = make_series(tmp_path / "b", description="ep2d_diff_tra_ADC", prefix="adc")
    archive = zip_files(t2 + adc)

    response = client.post(
        "/api/v1/studies/upload", files=[("files", ("study.zip", archive, "application/zip"))]
    )
    assert response.status_code == 201, response.text
    assert sorted(response.json()["modalities"]) == ["ADC", "T2W"]

    converted = client.post(f"/api/v1/studies/{response.json()['study_id']}/convert").json()
    assert sorted(n["modality"] for n in converted["nifti_files"]) == ["ADC", "T2W"]


def test_upload_multiple_separate_zips(client, tmp_path: Path):
    """Each series zipped separately (e.g. one .zip per modality) must all end up in one study."""
    t2 = make_series(tmp_path / "a", description="t2_tse_tra", prefix="t2")
    adc = make_series(tmp_path / "b", description="ep2d_diff_tra_ADC", prefix="adc")

    response = client.post(
        "/api/v1/studies/upload",
        files=[
            ("files", ("t2.zip", zip_files(t2), "application/zip")),
            ("files", ("adc.zip", zip_files(adc), "application/zip")),
        ],
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert sorted(body["modalities"]) == ["ADC", "T2W"]
    assert len(body["series"]) == 2


def test_upload_skips_non_dicom_files(client, t2w_series):
    files = as_upload(t2w_series) + [("files", ("readme.txt", b"hello", "text/plain"))]
    response = client.post("/api/v1/studies/upload", files=files)
    assert response.status_code == 201
    assert response.json()["skipped_files"] == 1


def test_upload_invalid_dicom(client):
    response = client.post("/api/v1/studies/upload", files=[("files", ("x.dcm", b"garbage", "application/dicom"))])
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_DICOM"


def test_upload_too_large(client, settings, t2w_series):
    settings.max_upload_mb = 0
    response = _upload(client, t2w_series)
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "UPLOAD_TOO_LARGE"


def test_convert_missing_required_modality(client, tmp_path: Path):
    adc = make_series(tmp_path / "adc", description="ADC map")
    study_id = _upload(client, adc).json()["study_id"]
    response = client.post(f"/api/v1/studies/{study_id}/convert")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "MISSING_REQUIRED_MODALITY"


def test_convert_unsupported_modality(client, tmp_path: Path):
    t1 = make_series(tmp_path / "t1", description="t1_vibe")
    study_id = _upload(client, t1).json()["study_id"]
    response = client.post(f"/api/v1/studies/{study_id}/convert")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "UNSUPPORTED_MODALITY"


def test_convert_failure_is_reported_without_details(client, tmp_path: Path):
    # Irregular slice spacing makes dicom2nifti reject the series.
    paths = make_series(tmp_path / "bad", num_slices=6)
    import pydicom

    ds = pydicom.dcmread(paths[3])
    ds.ImagePositionPatient = [0.0, 0.0, 40.0]
    ds.save_as(paths[3])

    study_id = _upload(client, paths).json()["study_id"]
    response = client.post(f"/api/v1/studies/{study_id}/convert")
    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "CONVERSION_FAILED"
    assert "Traceback" not in error["message"]
    assert client.get(f"/api/v1/studies/{study_id}").json()["status"] == "failed"


def test_unknown_ids(client):
    assert client.get("/api/v1/studies/" + "0" * 32).status_code == 404
    assert client.get("/api/v1/studies/../../etc").status_code == 404
    assert client.get("/api/v1/resources/" + "0" * 32).status_code == 404


def test_delete_study(client, t2w_series):
    study_id = _upload(client, t2w_series).json()["study_id"]
    assert client.delete(f"/api/v1/studies/{study_id}").status_code == 204
    assert client.get(f"/api/v1/studies/{study_id}").status_code == 404
