"""Test fixtures. All DICOM data is synthetic and contains no patient information."""

import io
import os
import zipfile
from collections.abc import Iterator
from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, MRImageStorage, generate_uid

from app.core.config import Settings
from app.db.models import Base
from app.db.session import Database
from app.main import create_app


def make_series(
    directory: Path,
    description: str = "t2_tse_tra",
    num_slices: int = 8,
    size: int = 32,
    prefix: str = "slice",
) -> list[Path]:
    """Write a synthetic axial MR series that dicom2nifti can convert."""
    directory.mkdir(parents=True, exist_ok=True)
    study_uid, series_uid, frame_uid = generate_uid(), generate_uid(), generate_uid()
    paths = []
    for i in range(num_slices):
        meta = FileMetaDataset()
        meta.MediaStorageSOPClassUID = MRImageStorage
        meta.MediaStorageSOPInstanceUID = generate_uid()
        meta.TransferSyntaxUID = ExplicitVRLittleEndian

        path = directory / f"{prefix}_{i:03d}.dcm"
        ds = FileDataset(str(path), {}, file_meta=meta, preamble=b"\0" * 128)
        ds.SOPClassUID = MRImageStorage
        ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
        ds.StudyInstanceUID = study_uid
        ds.SeriesInstanceUID = series_uid
        ds.FrameOfReferenceUID = frame_uid
        ds.Modality = "MR"
        ds.PatientName = "Anonymous"
        ds.PatientID = "ANON"
        ds.SeriesDescription = description
        ds.SeriesNumber = 1
        ds.InstanceNumber = i + 1
        ds.ImageType = ["ORIGINAL", "PRIMARY", "M", "ND"]
        ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
        ds.ImagePositionPatient = [0.0, 0.0, float(i * 3)]
        ds.SliceThickness = 3.0
        ds.PixelSpacing = [0.5, 0.5]
        ds.Rows = size
        ds.Columns = size
        ds.SamplesPerPixel = 1
        ds.PhotometricInterpretation = "MONOCHROME2"
        ds.BitsAllocated = 16
        ds.BitsStored = 16
        ds.HighBit = 15
        ds.PixelRepresentation = 0
        ds.RescaleIntercept = 0
        ds.RescaleSlope = 1
        ds.PixelData = (np.random.default_rng(i).integers(0, 1000, (size, size))).astype(np.uint16).tobytes()
        ds.save_as(path, enforce_file_format=True)
        paths.append(path)
    return paths


def zip_files(paths: list[Path]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for p in paths:
            archive.write(p, arcname=f"study/{p.name}")
    return buffer.getvalue()


def as_upload(paths: list[Path]) -> list[tuple[str, tuple[str, bytes, str]]]:
    return [("files", (p.name, p.read_bytes(), "application/dicom")) for p in paths]


@pytest.fixture
def settings(tmp_path: Path) -> Settings:
    """SQLite by default. Set TEST_DATABASE_URL (e.g. mysql+pymysql://user:pw@127.0.0.1:3306/aira_test) to run
    the suite against MySQL; that database is wiped before every test, so never point it at real data."""
    url = os.environ.get("TEST_DATABASE_URL")
    if url:
        db = Database(url)
        Base.metadata.drop_all(db.engine)
        db.engine.dispose()
    return Settings(storage_dir=tmp_path / "storage", required_modalities=["T2W"], database_url=url, _env_file=None)


def register(test_client: TestClient) -> str:
    """Register an anonymous user and make the client send its bearer token. Returns the user id."""
    body = test_client.post("/api/v1/users/anonymous").json()
    test_client.headers["Authorization"] = f"Bearer {body['token']}"
    return body["user_id"]


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    """A client registered as one anonymous user."""
    with TestClient(create_app(settings)) as test_client:
        register(test_client)
        yield test_client


@pytest.fixture
def other_client(client: TestClient) -> TestClient:
    """A second user talking to the same app."""
    other = TestClient(client.app)
    register(other)
    return other


@pytest.fixture
def t2w_series(tmp_path: Path) -> list[Path]:
    return make_series(tmp_path / "t2w", description="t2_tse_tra", prefix="t2")
