"""Mask editing API: label slices, saving versions, conflicts, validation, compare, refine. Synthetic data only."""

import hashlib
import io
from types import SimpleNamespace

import nibabel as nib
import numpy as np
import pytest
from PIL import Image

from app.models.study import MaskVersionRecord
from app.services import refine_service, slice_service
from app.services.storage import new_id
from tests.conftest import as_upload


@pytest.fixture
def study(client, settings, t2w_series):
    """A converted study with an AI mask version: a 4x4 blob on slice 2."""
    study_id = client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).json()["study_id"]
    client.post(f"/api/v1/studies/{study_id}/convert")
    nifti = client.get(f"/api/v1/studies/{study_id}").json()["nifti_files"][0]
    t2w = nib.load(settings.storage_dir / study_id / "nifti" / f"{nifti['resource_id']}.nii.gz")

    mask = np.zeros(nifti["shape"], dtype=np.uint8)
    mask[10:14, 12:16, 2] = 1
    version_id = new_id()
    seg_dir = settings.storage_dir / study_id / "segmentation"
    seg_dir.mkdir(parents=True, exist_ok=True)
    nib.save(nib.Nifti1Image(mask, t2w.affine), str(seg_dir / f"{version_id}.nii.gz"))
    client.app.state.storage.add_mask_version(
        study_id,
        MaskVersionRecord(
            version_id=version_id, labels={"1": "Lesion"}, volume_ml=0.1, file_name=f"{version_id}.nii.gz", model_name="m"
        ),
    )
    return SimpleNamespace(
        id=study_id, ai=version_id, mask=mask, shape=nifti["shape"], t2w=nifti["resource_id"], affine=t2w.affine,
        seg_dir=seg_dir,
    )


def label_slice(client, version_id, z) -> np.ndarray:
    response = client.get(f"/api/v1/masks/{version_id}/slices/{z}")
    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "image/png"
    return np.asarray(Image.open(io.BytesIO(response.content)))


def png(arr: np.ndarray) -> bytes:
    return slice_service.label_array_to_png(arr)


def save(client, study_id, base, slices: dict[int, np.ndarray], refined: str = ""):
    files = [("slices", (f"slice_{z:03d}.png", png(arr), "image/png")) for z, arr in slices.items()]
    return client.post(
        f"/api/v1/studies/{study_id}/mask/versions", data={"base_version_id": base, "refined_slices": refined}, files=files
    )


def sha(path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_plane_and_image_orientation_are_exact_inverses():
    plane = np.arange(5 * 7, dtype=np.uint8).reshape(5, 7)
    assert slice_service.plane_to_image(plane).shape == (7, 5)
    assert np.array_equal(slice_service.image_to_plane(slice_service.plane_to_image(plane)), plane)


def test_label_slice_matches_the_mask_and_lines_up_with_the_mri_pixel_for_pixel(client, settings, study):
    # Mark the brightest voxel of the T2W slice, then check both PNGs show it at the same pixel.
    z = 4
    t2w = np.asarray(nib.load(settings.storage_dir / study.id / "nifti" / f"{study.t2w}.nii.gz").dataobj)
    x, y = np.unravel_index(np.argmax(t2w[:, :, z]), t2w.shape[:2])
    mask = np.zeros(study.shape, dtype=np.uint8)
    mask[x, y, z] = 1
    version_id = new_id()
    nib.save(nib.Nifti1Image(mask, study.affine), str(study.seg_dir / f"{version_id}.nii.gz"))
    client.app.state.storage.add_mask_version(
        study.id, MaskVersionRecord(version_id=version_id, labels={"1": "Lesion"}, volume_ml=0, file_name=f"{version_id}.nii.gz")
    )

    labels = label_slice(client, version_id, z)
    mri = np.asarray(Image.open(io.BytesIO(client.get(f"/api/v1/resources/{study.t2w}/slices/{z}?full=true").content)))

    assert labels.shape == mri.shape == (study.shape[1], study.shape[0])  # rows = Y, columns = X
    assert labels.dtype == np.uint8 and int(labels.sum()) == 1
    row, col = np.argwhere(labels == 1)[0]
    assert (row, col) == (study.shape[1] - 1 - y, x)
    assert mri[row, col] == mri.max() == 255  # the marked voxel is the brightest pixel of the MRI slice


def test_saving_makes_a_new_version_and_never_touches_the_ai_mask(client, settings, study):
    ai_path = study.seg_dir / f"{study.ai}.nii.gz"
    ai_hash = sha(ai_path)
    edit = label_slice(client, study.ai, 2).copy()
    edit[0:3, 0:3] = 1  # nine new pixels

    response = save(client, study.id, study.ai, {2: edit}, refined="2")

    assert response.status_code == 201, response.text
    v1 = response.json()
    assert (v1["name"], v1["source"], v1["read_only"]) == ("Corrected v1", "manual_correction", False)
    assert v1["base_version_id"] == study.ai and v1["edited_slices"] == [2] and v1["refined_slices"] == [2]
    assert v1["slices_with_mask"] == [2]

    # The AI file and row are exactly as before; the new file keeps the T2W affine and holds the edit.
    assert sha(ai_path) == ai_hash
    saved = nib.load(study.seg_dir / f"{v1['version_id']}.nii.gz")
    assert np.allclose(saved.affine, study.affine) and saved.shape == tuple(study.shape)
    data = np.asarray(saved.dataobj)
    assert int(data.sum()) == int(study.mask.sum()) + 9 and data.dtype == np.uint8
    assert np.array_equal(np.delete(data, 2, axis=2), np.delete(study.mask, 2, axis=2))  # other slices untouched

    versions = client.get(f"/api/v1/studies/{study.id}/mask/versions").json()["versions"]
    assert [v["name"] for v in versions] == ["AI", "Corrected v1"] and versions[0]["read_only"] is True
    assert client.get(f"/api/v1/studies/{study.id}").json()["latest_mask_version_id"] == v1["version_id"]
    assert np.array_equal(label_slice(client, v1["version_id"], 2), edit)  # round trip is exact

    cmp = client.get(f"/api/v1/studies/{study.id}/mask/compare", params={"a": study.ai, "b": v1["version_id"]}).json()
    assert cmp["changed_voxels"] == 9
    assert cmp["dice"] == pytest.approx(2 * 16 / (16 + 25)) and cmp["iou"] == pytest.approx(16 / 25)
    assert cmp["volume_ml_b"] > cmp["volume_ml_a"]


def test_a_stale_base_is_a_409_and_a_chain_of_corrections_works(client, study):
    edit1 = label_slice(client, study.ai, 2).copy()
    edit1[0, 0] = 1
    v1 = save(client, study.id, study.ai, {2: edit1}).json()

    again = save(client, study.id, study.ai, {2: edit1})  # still based on the AI mask: not the latest any more
    assert again.status_code == 409
    assert again.json()["error"]["code"] == "VERSION_CONFLICT"

    edit2 = edit1.copy()
    edit2[1, 1] = 1
    v2 = save(client, study.id, v1["version_id"], {3: edit2 * 0 + edit2})
    assert v2.status_code == 201 and v2.json()["name"] == "Corrected v2"
    assert v2.json()["base_version_id"] == v1["version_id"]


@pytest.mark.parametrize(
    ("make", "message"),
    [
        (lambda s, e: {2: np.zeros((3, 3), np.uint8)}, "wrong size"),
        (lambda s, e: {2: np.where(e == 0, 7, 7).astype(np.uint8)}, "unknown label"),
        (lambda s, e: {999: e}, "outside this volume"),
        (lambda s, e: {2: e}, "no changes"),  # identical to the base
    ],
)
def test_invalid_slices_are_rejected_with_a_clear_message(client, study, make, message):
    base = label_slice(client, study.ai, 2)

    response = save(client, study.id, study.ai, make(study, base))

    assert response.status_code == 422, response.text
    assert response.json()["error"]["code"] == "INVALID_MASK_SLICE"
    assert message in response.json()["error"]["message"].lower()
    assert len(client.get(f"/api/v1/studies/{study.id}/mask/versions").json()["versions"]) == 1  # nothing was saved


def test_bad_uploads_are_rejected(client, study):
    base = label_slice(client, study.ai, 2)
    url = f"/api/v1/studies/{study.id}/mask/versions"
    data = {"base_version_id": study.ai}

    wrong_name = client.post(url, data=data, files=[("slices", ("evil.png", png(base), "image/png"))])
    not_png = client.post(url, data=data, files=[("slices", ("slice_002.png", b"not a png", "image/png"))])
    duplicate = client.post(url, data=data, files=[("slices", ("slice_002.png", png(base), "image/png"))] * 2)
    unknown_base = client.post(url, data={"base_version_id": "0" * 32}, files=[("slices", ("slice_002.png", png(base), "image/png"))])
    bad_refined = client.post(url, data={**data, "refined_slices": "x"}, files=[("slices", ("slice_002.png", png(base), "image/png"))])

    assert [r.status_code for r in (wrong_name, not_png, duplicate, bad_refined)] == [422] * 4
    assert unknown_base.status_code == 404


def test_another_user_cannot_read_edit_refine_or_compare(client, other_client, study):
    edit = label_slice(client, study.ai, 2).copy()
    edit[0, 0] = 1
    files = [("slices", ("slice_002.png", png(edit), "image/png"))]

    assert other_client.get(f"/api/v1/masks/{study.ai}/slices/2").status_code == 404
    assert other_client.post(f"/api/v1/studies/{study.id}/mask/versions", data={"base_version_id": study.ai}, files=files).status_code == 404
    assert other_client.get(f"/api/v1/studies/{study.id}/mask/compare", params={"a": study.ai, "b": study.ai}).status_code == 404
    refine = other_client.post(
        f"/api/v1/studies/{study.id}/mask/refine",
        data={"base_version_id": study.ai, "slice_index": 2},
        files={"edited_slice": ("e.png", png(edit), "image/png")},
    )
    assert refine.status_code == 404


def test_compare_of_a_version_with_itself_is_perfect(client, study):
    cmp = client.get(f"/api/v1/studies/{study.id}/mask/compare", params={"a": study.ai, "b": study.ai}).json()
    assert (cmp["dice"], cmp["iou"], cmp["changed_voxels"]) == (1.0, 1.0, 0)


def refine(client, study, edit, **data):
    return client.post(
        f"/api/v1/studies/{study.id}/mask/refine",
        data={"base_version_id": study.ai, "slice_index": 2, **data},
        files={"edited_slice": ("edit.png", png(edit), "image/png")},
    )


def test_refine_returns_a_proposal_and_stores_nothing(client, study):
    base = label_slice(client, study.ai, 2)
    edit = base.copy()
    edit[18:24, 18:24] = 1

    response = refine(client, study, edit, band_width_vox=3)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["slice_index"] == 2 and body["method"] == "random_walker" and body["band_width_vox"] == 3
    proposed = np.asarray(Image.open(io.BytesIO(__import__("base64").b64decode(body["proposed_slice_png_base64"]))))
    assert proposed.shape == edit.shape and set(np.unique(proposed).tolist()) <= {0, 1}
    assert body["changed_pixels"] == int((proposed != edit).sum()) and body["runtime_ms"] >= 0
    assert len(client.get(f"/api/v1/studies/{study.id}/mask/versions").json()["versions"]) == 1  # stateless


def test_refine_with_no_edit_returns_the_slice_unchanged(client, study):
    base = label_slice(client, study.ai, 2)
    body = refine(client, study, base).json()
    assert body["changed_pixels"] == 0


def test_refine_validation(client, study):
    edit = label_slice(client, study.ai, 2).copy()
    edit[0, 0] = 1
    assert refine(client, study, edit, method="grabcut").status_code == 422
    assert refine(client, study, edit, band_width_vox=99).status_code == 422
    assert refine(client, study, edit, label=5).status_code == 422
    assert refine(client, study, np.zeros((3, 3), np.uint8)).status_code == 422
    assert refine(client, study, edit, slice_index=999).status_code in (400, 422)


def test_refine_that_takes_too_long_is_a_504_and_leaves_the_edit_alone(client, study, monkeypatch):
    import time

    monkeypatch.setattr(refine_service, "refine_slice", lambda *a, **k: time.sleep(0.5))
    client.app.state.settings.refine_timeout_seconds = 0.05
    edit = label_slice(client, study.ai, 2).copy()
    edit[0, 0] = 1

    response = refine(client, study, edit)

    assert response.status_code == 504
    assert response.json()["error"]["code"] == "REFINE_TIMEOUT"


def test_refine_never_changes_the_ai_pixels_the_user_did_not_touch(client, study):
    """The edit is drawn against the AI lesion; the proposal keeps every untouched AI pixel."""
    base = label_slice(client, study.ai, 2)
    edit = base.copy()
    edit[10:14, 16:21] = 1  # extends the lesion to the right

    body = refine(client, study, edit, band_width_vox=6).json()
    proposed = np.asarray(Image.open(io.BytesIO(__import__("base64").b64decode(body["proposed_slice_png_base64"]))))

    assert (proposed[base == 1] == 1).all()
