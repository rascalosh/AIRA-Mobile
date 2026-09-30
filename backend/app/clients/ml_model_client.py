"""Adapter for the existing, external ML Model API (spec §10).

The ML model is pre-trained and out of scope for this project; the backend only talks to it
through this interface so the concrete service can be swapped (mock → real) without touching
business logic. Implementations arrive in Phase 3.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ModelInput:
    modality: str
    nifti_path: Path


@dataclass
class SegmentationOutput:
    mask_path: Path
    labels: dict[int, str]


class MLModelClient(ABC):
    @abstractmethod
    async def segment(self, inputs: list[ModelInput], output_dir: Path) -> SegmentationOutput:
        """Send model-ready NIfTI volumes and return the segmentation mask."""

    @abstractmethod
    async def health(self) -> bool:
        """Whether the ML service is reachable."""
