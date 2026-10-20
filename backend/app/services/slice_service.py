"""On-demand PNG slice extraction from converted NIfTI volumes.

Rendering happens on the backend rather than shipping raw NIfTI/gzip bytes
for the mobile app to decode (spec §5: keep heavy numeric work off the
phone) — the app just fetches and displays an image per slice.
"""

import io
import logging
import threading
from pathlib import Path

import nibabel as nib
import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion

from app.core import errors

logger = logging.getLogger(__name__)

_MAX_CACHE_ENTRIES = 4


class _VolumeCache:
    """A tiny bounded cache of decoded, windowed volumes, keyed by resource id.

    Decoding the .nii.gz and computing its display window is the expensive
    part of serving a slice; caching it keeps interactive slice scrubbing
    fast without re-reading the file on every request. Bounded and FIFO so
    it can never grow without limit across many studies in one process.
    """

    def __init__(self, max_entries: int = _MAX_CACHE_ENTRIES) -> None:
        self._max_entries = max_entries
        self._lock = threading.Lock()
        self._order: list[str] = []
        self._data: dict[str, tuple[np.ndarray, float, float]] = {}

    def get(self, resource_id: str) -> tuple[np.ndarray, float, float] | None:
        with self._lock:
            return self._data.get(resource_id)

    def put(self, resource_id: str, value: tuple[np.ndarray, float, float]) -> None:
        with self._lock:
            if resource_id not in self._data and len(self._order) >= self._max_entries:
                oldest = self._order.pop(0)
                self._data.pop(oldest, None)
            if resource_id not in self._data:
                self._order.append(resource_id)
            self._data[resource_id] = value

    def discard(self, resource_id: str) -> None:
        with self._lock:
            self._data.pop(resource_id, None)
            if resource_id in self._order:
                self._order.remove(resource_id)


_cache = _VolumeCache()


def _load_volume(resource_id: str, path: Path) -> tuple[np.ndarray, float, float]:
    cached = _cache.get(resource_id)
    if cached is not None:
        return cached

    data = nib.load(str(path)).get_fdata(dtype=np.float32)  # float32: half the memory of the default
    if data.ndim not in (3, 4):
        raise errors.unsupported_volume()

    # Display window computed once per volume (not per slice) so brightness
    # stays stable while scrubbing, instead of each slice being independently
    # contrast-stretched.
    finite = data[np.isfinite(data)]
    if finite.size == 0:
        low, high = 0.0, 1.0
    else:
        low, high = (float(v) for v in np.percentile(finite, [1, 99]))
        if high <= low:
            # Degenerate distribution (e.g. a constant volume) — fall back to
            # min/max; render_slice_png's span<=0 check handles the all-equal case.
            low, high = float(finite.min()), float(finite.max())

    result = (data, low, high)
    _cache.put(resource_id, result)
    return result


def slice_count(resource_id: str, path: Path) -> int:
    data, _, _ = _load_volume(resource_id, path)
    return int(data.shape[2])


def render_slice_png(resource_id: str, path: Path, index: int, max_dim: int | None = 512) -> bytes:
    data, low, high = _load_volume(resource_id, path)

    if index < 0 or index >= data.shape[2]:
        raise errors.invalid_slice_index()

    # 4D data (e.g. multi-b-value DWI) carries extra volumes in the last
    # axis; show the first one. Slicing stays along axis 2 — the axial axis
    # after dicom2nifti's reorientation (see nifti_service.py).
    plane = data[:, :, index, 0] if data.ndim == 4 else data[:, :, index]

    # A reasonable default presentation: transpose so image rows run
    # superior→inferior, then flip vertically. Fine orientation tuning
    # (left/right convention) should be checked against real clinical data.
    plane = np.flipud(plane.T)

    span = high - low
    if span <= 0:
        normalized = np.zeros_like(plane, dtype=np.uint8)
    else:
        clipped = np.clip(plane, low, high)
        normalized = ((clipped - low) / span * 255).astype(np.uint8)

    image = Image.fromarray(normalized, mode="L")
    if max_dim and max(image.size) > max_dim:
        image.thumbnail((max_dim, max_dim), Image.LANCZOS)

    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def render_mask_overlay_png(path: Path, index: int, max_dim: int = 512) -> bytes:
    """A mask slice as RGBA: 40% cyan fill with a solid outline, transparent elsewhere.

    Uses the same orientation and downscaling as `render_slice_png`, so the two PNGs line up.
    """
    mask = np.asarray(nib.load(str(path)).dataobj)
    if index < 0 or index >= mask.shape[2]:
        raise errors.invalid_slice_index()

    plane = np.flipud(mask[:, :, index].T) > 0
    edge = plane & ~binary_erosion(plane)
    rgba = np.zeros((*plane.shape, 4), dtype=np.uint8)
    rgba[plane] = (34, 211, 238, 102)
    rgba[edge] = (34, 211, 238, 255)

    image = Image.fromarray(rgba, mode="RGBA")
    if max(image.size) > max_dim:
        image.thumbnail((max_dim, max_dim), Image.NEAREST)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


# -- editing: label slices -----------------------------------------------------------------
# A slice travels as an image (rows = Y flipped, columns = X). `plane_to_image` and `image_to_plane` are exact
# inverses, and the MRI slice and the label slice both use them, so the two always line up pixel for pixel.

_MAX_LABEL_PIXELS = 4096 * 4096


def plane_to_image(plane: np.ndarray) -> np.ndarray:
    return np.flipud(plane.T)


def image_to_plane(image: np.ndarray) -> np.ndarray:
    return np.flipud(image).T


def label_array_to_png(image: np.ndarray) -> bytes:
    buffer = io.BytesIO()
    Image.fromarray(image.astype(np.uint8), mode="L").save(buffer, format="PNG")
    return buffer.getvalue()


def render_label_png(path: Path, index: int) -> bytes:
    """One mask slice as a lossless 8-bit PNG at native size; the pixel value is the label (0 = background)."""
    mask = np.asarray(nib.load(str(path)).dataobj)
    if index < 0 or index >= mask.shape[2]:
        raise errors.invalid_slice_index()
    return label_array_to_png(plane_to_image(mask[:, :, index].astype(np.uint8)))


def decode_label_png(data: bytes) -> np.ndarray:
    """An uploaded label PNG as a 2D uint8 array in image orientation. Gray or RGB(A) PNGs are accepted (the red
    channel is the label: an opaque gray image has R = G = B)."""
    try:
        image = Image.open(io.BytesIO(data))
        if image.format != "PNG" or image.width * image.height > _MAX_LABEL_PIXELS:
            raise ValueError("not a usable PNG")
        if image.mode not in ("L", "RGB", "RGBA"):
            raise ValueError("unsupported PNG mode")
        image.load()
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        raise errors.invalid_mask_slice("A mask slice could not be read. Please try again.") from exc
    return np.asarray(image if image.mode == "L" else image.getchannel("R"), dtype=np.uint8)


def image_plane(resource_id: str, path: Path, index: int) -> np.ndarray:
    """The raw intensities of one slice in the same orientation as the PNGs (for refinement)."""
    data, _, _ = _load_volume(resource_id, path)
    if index < 0 or index >= data.shape[2]:
        raise errors.invalid_slice_index()
    plane = data[:, :, index, 0] if data.ndim == 4 else data[:, :, index]
    return plane_to_image(plane)


def discard_cache(resource_id: str) -> None:
    _cache.discard(resource_id)
