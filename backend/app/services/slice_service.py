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

from app.core import errors

logger = logging.getLogger(__name__)

_MAX_CACHE_ENTRIES = 8


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

    data = nib.load(str(path)).get_fdata()
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


def render_slice_png(resource_id: str, path: Path, index: int, max_dim: int = 512) -> bytes:
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
    if max(image.size) > max_dim:
        image.thumbnail((max_dim, max_dim), Image.LANCZOS)

    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def discard_cache(resource_id: str) -> None:
    _cache.discard(resource_id)
