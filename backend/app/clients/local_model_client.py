"""In-process implementation of the ML adapter (spec §10): runs the bundled PyTorch model.

To replace the model, point `MODEL_PATH` at new weights of the same architecture. A different
architecture needs its own class next to `prostate_denseunet.py` and a change to `_load()` below.

Inputs mirror the training data exactly (verified against the notebook's own outputs; no intensity
normalisation was used in training). Each modality is handled on its own grid: reoriented to LPS index
order, resampled to the training spacing (T2W 0.5x0.5x3 mm, ADC and DWI 1.5x1.5x3 mm), then resized to
the fixed network shape (T2W 256x256x32, ADC/DWI 88x88x32, ADC first). The mask is mapped back onto the
T2W grid.
"""

import asyncio
import logging
import threading
from pathlib import Path

import nibabel as nib
import numpy as np
import torch
from nibabel import orientations as ori
from skimage.transform import resize

from app.clients.ml_model_client import MLModelClient, ModelInput, SegmentationOutput
from app.core import errors
from app.ml.prostate_denseunet import load_model

logger = logging.getLogger(__name__)

T2_SHAPE = (256, 256, 32)
DW_SHAPE = (88, 88, 32)
TRAINING_SPACING = {"T2W": (0.5, 0.5, 3.0), "ADC": (1.5, 1.5, 3.0), "DWI": (1.5, 1.5, 3.0)}
_LPS = ori.axcodes2ornt(("L", "P", "S"))  # PI-CAI arrays are LPS-indexed (SimpleITK order)


def _resize(volume: np.ndarray, shape: tuple[int, int, int], anti_aliasing: bool = True) -> np.ndarray:
    """The notebook's resize: linear, edge padding, anti-aliased, intensities preserved."""
    return resize(
        volume, shape, order=1, mode="edge", anti_aliasing=anti_aliasing, preserve_range=True
    ).astype(np.float32)


def to_network_input(volume: np.ndarray, zooms: tuple[float, ...], modality: str, shape: tuple[int, int, int]):
    """Resample to the training spacing (like the training data), then resize to the network shape."""
    target = tuple(max(1, round(n * z / s)) for n, z, s in zip(volume.shape, zooms, TRAINING_SPACING[modality]))
    if target != volume.shape:
        volume = _resize(volume, target, anti_aliasing=False)  # a plain linear resample, no smoothing
    return _resize(volume, shape)


def _load_lps(path: Path, last_volume: bool = False):
    """A NIfTI as an LPS-indexed array with its voxel size, plus the transforms to and from that order."""
    img = nib.load(str(path))
    if len(img.shape) == 4:  # multi-b-value DWI: the last volume is the highest b-value
        img = nib.funcs.four_to_three(img)[-1 if last_volume else 0]
    native = ori.io_orientation(img.affine)
    to_lps = ori.ornt_transform(native, _LPS)
    zooms = np.empty(3)
    zooms[to_lps[:, 0].astype(int)] = img.header.get_zooms()[:3]
    data = ori.apply_orientation(np.nan_to_num(img.get_fdata(dtype=np.float32)), to_lps)
    return img, data, tuple(zooms), ori.ornt_transform(_LPS, native)


class LocalTorchClient(MLModelClient):
    def __init__(self, weights_path: Path) -> None:
        self.weights_path = Path(weights_path)
        self._model: torch.nn.Module | None = None
        self._lock = threading.Lock()

    def _load(self) -> torch.nn.Module:
        with self._lock:
            if self._model is None:
                if not self.weights_path.is_file():
                    raise errors.model_unavailable()
                self._model = load_model(self.weights_path)
            return self._model

    async def health(self) -> bool:
        return self.weights_path.is_file()

    async def segment(self, inputs: list[ModelInput], output_dir: Path) -> SegmentationOutput:
        return await asyncio.to_thread(self._segment, inputs, output_dir)

    def probability(self, paths: dict[str, Path]):
        """Run the network. Returns (probabilities on the network grid, T2W image, T2W LPS shape, from-LPS transform)."""
        model = self._load()
        t2_img, t2, t2_zooms, from_lps = _load_lps(paths["T2W"])
        _, adc, adc_zooms, _ = _load_lps(paths["ADC"])
        _, dwi, dwi_zooms, _ = _load_lps(paths["DWI"], last_volume=True)

        t2_in = torch.from_numpy(to_network_input(t2, t2_zooms, "T2W", T2_SHAPE))[None, None]
        dw_in = torch.from_numpy(
            np.stack(
                [
                    to_network_input(adc, adc_zooms, "ADC", DW_SHAPE),
                    to_network_input(dwi, dwi_zooms, "DWI", DW_SHAPE),
                ]
            )
        )[None]
        with torch.no_grad():
            prob = torch.sigmoid(model(t2_in, dw_in))[0, 0].numpy()
        return prob, t2_img, t2.shape, from_lps

    def _segment(self, inputs: list[ModelInput], output_dir: Path) -> SegmentationOutput:
        prob, t2_img, t2_shape, from_lps = self.probability({i.modality: i.nifti_path for i in inputs})

        mask = (_resize(prob, t2_shape, anti_aliasing=False) > 0.5).astype(np.uint8)
        mask = ori.apply_orientation(mask, from_lps)

        output_dir.mkdir(parents=True, exist_ok=True)
        mask_path = output_dir / "mask.nii.gz"
        out = nib.Nifti1Image(mask, t2_img.affine)
        out.set_data_dtype(np.uint8)
        nib.save(out, str(mask_path))
        return SegmentationOutput(mask_path=mask_path, labels={1: "Lesion"})
