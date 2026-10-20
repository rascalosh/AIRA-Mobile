"""Edge-fitting refinement of a hand-edited mask slice (classical image processing, no learning).

A rough edit is fitted to the image boundary by a seeded random walker restricted to a band around the edited
boundary, followed by morphological cleanup. It only produces a *proposal*: nothing is stored, and the user
accepts or rejects it in the app.

Guarantees (tested): the AI mask is left alone: its untouched pixels never change (`protected`), and the refined
boundary is the boundary of the user's own annotation, so the AI mask's edge is never grown or smoothed. Nothing
changes outside the *neighbourhood* of the edit (the changed pixels dilated by the band width); pixels of other labels are never overwritten; an edit identical to the base is returned
unchanged. All arrays are 2D and in the same orientation; orientation does not matter to the algorithm.
"""

from dataclasses import dataclass

import numpy as np
from scipy import ndimage as ndi
from skimage.morphology import disk
from skimage.restoration import denoise_tv_chambolle
from skimage.segmentation import random_walker

_CROP_MARGIN = 3  # pixels of seeds kept around the band so the walker has context


@dataclass(frozen=True)
class RefineParams:
    band_width_vox: int = 3  # how far the boundary may move (1-8)
    # Edge sensitivity. Tuned on synthetic scenes with a known boundary (noise, blur and contrast varied, held-out
    # set): 800 with denoising beat the skimage default of 130 on raw pixels (mean Dice gain +0.07 vs +0.03,
    # regressions 2% vs 15%). Not validated on real lesions: there is no ground truth yet.
    beta: float = 800.0
    denoise_weight: float = 0.12  # total-variation denoising of the patch before the walk; 0 disables it
    min_component_vox: int = 10  # islands smaller than this, inside the neighbourhood, are removed
    smoothing_radius_vox: int = 1  # 0 disables smoothing
    keep_largest_component: bool = False  # off for lesions: there can be several


def _core(fg: np.ndarray, width: int) -> np.ndarray:
    """The part of `fg` that is certainly foreground: eroded by the band width, or for a small object by less."""
    for k in range(width, 0, -1):
        core = ndi.binary_erosion(fg, iterations=k)
        if core.any():
            return core
    edt = ndi.distance_transform_edt(fg)
    return edt >= edt.max()


def _cleanup(fg: np.ndarray, near: np.ndarray, p: RefineParams) -> np.ndarray:
    cleaned = ndi.binary_fill_holes(fg)
    if p.smoothing_radius_vox > 0:
        r = p.smoothing_radius_vox
        se = disk(r)
        padded = np.pad(cleaned, r + 1, mode="edge")  # keeps closing/opening from eating the image border
        closed = ndi.binary_closing(padded, structure=se)
        opened = ndi.binary_opening(closed, structure=se)
        unpad = (slice(r + 1, -(r + 1)),) * 2
        closed, opened = closed[unpad], opened[unpad]
        # Opening can erase a very small object; keep the closed version rather than lose the edit.
        cleaned = opened if opened[near].any() or not closed[near].any() else closed

    labels, count = ndi.label(cleaned)
    if count:
        sizes = ndi.sum(cleaned, labels, range(1, count + 1))
        largest = int(np.argmax(sizes)) + 1
        for i in range(1, count + 1):
            inside = labels == i
            if not near[inside].all():
                continue  # touches the untouched part of the slice: leave it alone
            if sizes[i - 1] < p.min_component_vox or (p.keep_largest_component and i != largest):
                cleaned[inside] = False
    return cleaned


def refine_slice(
    image: np.ndarray,
    base: np.ndarray,
    edited: np.ndarray,
    label: int,
    params: RefineParams = RefineParams(),
    protected: np.ndarray | None = None,
) -> np.ndarray:
    """Return the proposed label slice for `edited` (the user's version of `base`), fitted to `image`.

    `protected` marks the AI mask's pixels: those the user did not change stay exactly as they are, so only the
    user's own annotation is refined.
    """
    w = params.band_width_vox
    fg = edited == label
    changed = edited != base
    if not changed.any() or not fg.any():
        return edited.copy()
    frozen = fg & ~changed & protected if protected is not None else np.zeros_like(fg)

    mine = fg & ~frozen  # the user's own annotation: the only shape whose boundary is refined
    if not mine.any():
        return edited.copy()

    near = ndi.binary_dilation(changed, iterations=w)
    other = (edited != 0) & ~fg  # other labels: background for the walker, never overwritten
    band = ndi.binary_dilation(mine, iterations=w) & ~_core(mine, w) & near & ~other & ~frozen
    if not band.any():
        return edited.copy()

    ys, xs = np.nonzero(band)
    y0, y1 = max(ys.min() - _CROP_MARGIN, 0), min(ys.max() + _CROP_MARGIN + 1, edited.shape[0])
    x0, x1 = max(xs.min() - _CROP_MARGIN, 0), min(xs.max() + _CROP_MARGIN + 1, edited.shape[1])
    crop = (slice(y0, y1), slice(x0, x1))

    seeds = np.where(fg[crop], 2, 1)
    seeds[band[crop]] = 0  # the band is what the walker decides
    patch = image[crop].astype(np.float64)
    lo, hi = np.percentile(patch, [1, 99])
    if not ((seeds == 1).any() and (seeds == 2).any()) or hi <= lo:
        return edited.copy()
    patch = np.clip((patch - lo) / (hi - lo), 0.0, 1.0)
    if params.denoise_weight > 0:
        patch = denoise_tv_chambolle(patch, weight=params.denoise_weight)  # MRI noise otherwise makes the edge ragged

    walked = random_walker(patch, seeds, beta=params.beta, mode="bf") == 2

    out = edited.copy()
    view, in_band = out[crop], band[crop]
    view[in_band & walked] = label
    view[in_band & ~walked & (edited[crop] == label)] = 0

    result = out == label
    cleaned = _cleanup(result, near, params)
    out[near & cleaned & ~result & ~other] = label
    out[near & result & ~cleaned & ~frozen] = 0
    return out
