"""Refinement algorithm tests on synthetic images with a known true boundary."""

import numpy as np
import pytest
from scipy import ndimage as ndi

from app.services.refine_service import RefineParams, refine_slice

SIZE = 96
rng = np.random.default_rng(0)


def disk(cy, cx, r, size=SIZE):
    yy, xx = np.ogrid[:size, :size]
    return (yy - cy) ** 2 + (xx - cx) ** 2 <= r * r


def dice(a, b):
    return 2 * (a & b).sum() / max(1, a.sum() + b.sum())


@pytest.fixture
def scene():
    truth = disk(48, 48, 16)
    image = np.where(truth, 200.0, 60.0) + rng.normal(0, 4, (SIZE, SIZE))
    return image, truth


def test_a_sloppy_edit_is_fitted_to_the_image_boundary(scene):
    image, truth = scene
    base = np.zeros((SIZE, SIZE), np.uint8)
    edited = disk(50, 51, 19).astype(np.uint8)  # too big and off-centre, as a rough drawing would be

    # The boundary can move at most the band width, so the band must reach the true edge (up to ~6.6 px away).
    proposed = refine_slice(image, base, edited, 1, RefineParams(band_width_vox=8))

    assert dice(proposed == 1, truth) > dice(edited == 1, truth)
    assert dice(proposed == 1, truth) > 0.9


def test_a_narrow_band_limits_how_far_the_boundary_can_move(scene):
    image, truth = scene
    edited = disk(50, 51, 19).astype(np.uint8)
    narrow = refine_slice(image, np.zeros_like(edited), edited, 1, RefineParams(band_width_vox=2))
    wide = refine_slice(image, np.zeros_like(edited), edited, 1, RefineParams(band_width_vox=8))

    assert dice(wide == 1, truth) > dice(narrow == 1, truth) > dice(edited == 1, truth)
    # With a band of 2 no pixel further than 2 px (+ cleanup) from the user's outline can change.
    far = ~ndi.binary_dilation(ndi.binary_dilation(edited == 1, iterations=2) ^ ndi.binary_erosion(edited == 1, iterations=2), iterations=1) & (narrow != edited)
    assert not far.any()


def test_nothing_changes_outside_the_neighbourhood_of_the_edit(scene):
    image, truth = scene
    base = truth.astype(np.uint8)
    base[5:9, 5:9] = 1  # a separate island far from the edit
    edited = base.copy()
    edited[70:76, 60:66] = 1  # the user's edit
    p = RefineParams(band_width_vox=3)

    proposed = refine_slice(image, base, edited, 1, p)

    near = ndi.binary_dilation(edited != base, iterations=2 * p.band_width_vox)
    assert np.array_equal(proposed[~near], edited[~near])
    assert (proposed == 1)[5:9, 5:9].all()  # the far island is untouched


def test_other_labels_are_never_overwritten(scene):
    image, truth = scene
    base = np.zeros((SIZE, SIZE), np.uint8)
    base[40:56, 20:30] = 2
    edited = base.copy()
    edited[truth] = 1
    edited[40:56, 20:30] = 2

    proposed = refine_slice(image, base, edited, 1)

    assert np.array_equal(proposed == 2, base == 2)


def test_an_edit_equal_to_the_base_is_returned_unchanged(scene):
    image, truth = scene
    base = truth.astype(np.uint8)

    proposed = refine_slice(image, base, base, 1)

    assert np.array_equal(proposed, base) and proposed is not base


def test_erasing_everything_or_a_tiny_object_does_not_fail(scene):
    image, _ = scene
    base = disk(48, 48, 10).astype(np.uint8)

    erased = refine_slice(image, base, np.zeros_like(base), 1)
    assert not erased.any()

    tiny = np.zeros_like(base)
    tiny[48:50, 48:50] = 1  # smaller than the band: the walker needs a fallback seed
    out = refine_slice(image, np.zeros_like(base), tiny, 1)
    assert out.shape == tiny.shape


@pytest.mark.parametrize("width", [1, 4, 8])
def test_every_allowed_band_width_runs(scene, width):
    image, truth = scene
    edited = ndi.binary_dilation(truth, iterations=2).astype(np.uint8)
    out = refine_slice(image, np.zeros_like(edited), edited, 1, RefineParams(band_width_vox=width))
    assert set(np.unique(out).tolist()) <= {0, 1}


def test_a_flat_image_gives_back_the_edit(scene):
    _, truth = scene
    edited = truth.astype(np.uint8)
    out = refine_slice(np.full((SIZE, SIZE), 10.0), np.zeros_like(edited), edited, 1)
    assert np.array_equal(out, edited)


def test_denoising_helps_on_a_noisy_image():
    """On a noisy slice the tuned defaults (denoise + high beta) beat the plain walker, averaged over several scenes."""
    local = np.random.default_rng(7)
    tuned, plain = [], []
    for _ in range(12):
        truth = disk(48, 48, 14)
        image = np.where(truth, 150.0, 90.0) + local.normal(0, 18, (SIZE, SIZE))
        edited = disk(50, 51, 17).astype(np.uint8)
        base = np.zeros_like(edited)
        tuned.append(dice(refine_slice(image, base, edited, 1, RefineParams(band_width_vox=5)) == 1, truth))
        plain.append(
            dice(
                refine_slice(image, base, edited, 1, RefineParams(band_width_vox=5, beta=130.0, denoise_weight=0)) == 1,
                truth,
            )
        )
    assert np.mean(tuned) > np.mean(plain)


def test_untouched_ai_pixels_are_never_changed(scene):
    """A stroke drawn against the AI mask is refined, but the AI's own pixels stay exactly as they were."""
    image, truth = scene
    ai = disk(48, 48, 10).astype(np.uint8)  # smaller than the true lesion, so the image pulls the edge outward
    edited = ai.copy()
    edited[44:52, 56:64] = 1  # the user's stroke, touching the AI mask
    p = RefineParams(band_width_vox=6)

    protected = refine_slice(image, ai, edited, 1, p, protected=ai == 1)

    assert (protected[ai == 1] == 1).all()
    assert not np.array_equal(protected, edited)  # the user's own edit was still refined


def test_the_ai_masks_edge_is_not_grown_or_smoothed(scene):
    """Refining a stroke next to the AI mask leaves the AI's edge alone, even where the image invites it to grow."""
    image, truth = scene  # the true lesion (r=16) is larger than the AI mask (r=10): the image pulls the AI edge outward
    ai = disk(48, 48, 10).astype(np.uint8)
    edited = ai.copy()
    edited[44:52, 58:64] = 1  # the user's own stroke, a few pixels from the AI mask on the right
    p = RefineParams(band_width_vox=6)

    proposed = refine_slice(image, ai, edited, 1, p, protected=ai == 1)

    changed = edited != ai
    reach = ndi.binary_dilation(changed, iterations=p.band_width_vox)
    assert np.array_equal(proposed[~reach], edited[~reach])  # nothing moves farther than the band from the stroke
    assert (proposed[ai == 1] == 1).all()
    # Away from the stroke (the left half) the AI mask's outline is exactly what the AI produced.
    assert np.array_equal(proposed[:, :48], edited[:, :48])


def test_a_pure_erase_leaves_the_ai_mask_as_the_user_left_it(scene):
    image, _ = scene
    ai = disk(48, 48, 12).astype(np.uint8)
    edited = ai.copy()
    edited[44:52, 50:58] = 0  # the user erased part of the AI mask: there is no annotation of theirs to refine
    proposed = refine_slice(image, ai, edited, 1, RefineParams(band_width_vox=4), protected=ai == 1)
    assert np.array_equal(proposed, edited)
