from pathlib import Path

import pytest
from pydicom.dataset import Dataset

from app.models.study import Modality
from app.services.dicom_service import classify_modality, read_header
from tests.conftest import make_series


def _ds(**attrs) -> Dataset:
    ds = Dataset()
    for key, value in attrs.items():
        setattr(ds, key, value)
    return ds


@pytest.mark.parametrize(
    ("attrs", "expected"),
    [
        ({"SeriesDescription": "t2_tse_tra"}, Modality.T2W),
        ({"SeriesDescription": "T2W AX"}, Modality.T2W),
        ({"SeriesDescription": "ep2d_diff_b50_400_800_tra_TRACEW"}, Modality.DWI),
        ({"SeriesDescription": "ax dwi b1000"}, Modality.DWI),
        ({"SeriesDescription": "ep2d_diff_tra_ADC"}, Modality.ADC),
        ({"SeriesDescription": "diffusion", "ImageType": ["DERIVED", "PRIMARY", "ADC"]}, Modality.ADC),
        ({"SeriesDescription": "ax", "EchoTime": 100, "RepetitionTime": 4000}, Modality.T2W),
        ({"SeriesDescription": "t1_vibe_dyn"}, Modality.UNKNOWN),
        ({}, Modality.UNKNOWN),
    ],
)
def test_classify_modality(attrs, expected):
    assert classify_modality(_ds(**attrs)) == expected


def test_read_header_accepts_valid_mr(tmp_path: Path):
    path = make_series(tmp_path, num_slices=1)[0]
    header = read_header(path)
    assert header is not None
    assert header.series_uid


def test_read_header_rejects_non_dicom(tmp_path: Path):
    path = tmp_path / "notes.txt"
    path.write_text("not a dicom file")
    assert read_header(path) is None
