import io
from pathlib import Path

from PIL import Image

from tests.conftest import as_upload


def _converted_resource(client, t2w_series) -> tuple[str, str]:
    upload = client.post("/api/v1/studies/upload", files=as_upload(t2w_series))
    study_id = upload.json()["study_id"]
    converted = client.post(f"/api/v1/studies/{study_id}/convert").json()
    return study_id, converted["nifti_files"][0]["resource_id"]


def test_slice_returns_png_matching_volume_shape(client, t2w_series):
    _, resource_id = _converted_resource(client, t2w_series)

    response = client.get(f"/api/v1/resources/{resource_id}/slices/0")

    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "image/png"
    image = Image.open(io.BytesIO(response.content))
    assert image.mode == "L"
    # The synthetic fixture is 32x32 slices (see tests/conftest.py).
    assert image.size == (32, 32)


def test_every_slice_is_reachable(client, t2w_series):
    _, resource_id = _converted_resource(client, t2w_series)

    # The fixture has 8 slices (tests/conftest.py's make_series default).
    for index in range(8):
        response = client.get(f"/api/v1/resources/{resource_id}/slices/{index}")
        assert response.status_code == 200, f"slice {index}: {response.text}"
        Image.open(io.BytesIO(response.content)).verify()


def test_slice_out_of_range(client, t2w_series):
    _, resource_id = _converted_resource(client, t2w_series)

    response = client.get(f"/api/v1/resources/{resource_id}/slices/999")

    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_SLICE_INDEX"

    response = client.get(f"/api/v1/resources/{resource_id}/slices/-1")
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_SLICE_INDEX"


def test_slice_unknown_resource(client):
    response = client.get("/api/v1/resources/" + "0" * 32 + "/slices/0")
    assert response.status_code == 404


def test_repeat_request_is_deterministic(client, t2w_series):
    """A second request for the same slice (served from the volume cache) matches the first byte-for-byte."""
    _, resource_id = _converted_resource(client, t2w_series)

    first = client.get(f"/api/v1/resources/{resource_id}/slices/0")
    second = client.get(f"/api/v1/resources/{resource_id}/slices/0")

    assert first.status_code == second.status_code == 200
    assert first.content == second.content


def test_downscales_large_slices(client, tmp_path: Path):
    from tests.conftest import make_series

    big = make_series(tmp_path / "big", size=600)
    _, resource_id = _converted_resource(client, big)

    response = client.get(f"/api/v1/resources/{resource_id}/slices/0")

    assert response.status_code == 200
    image = Image.open(io.BytesIO(response.content))
    assert max(image.size) <= 512
