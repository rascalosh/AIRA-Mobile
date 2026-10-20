"""Receiving, validating and grouping uploaded DICOM files.

Client-supplied file names and zip member paths are never used on disk: every file is stored
under a server-generated name, which also rules out path traversal.
"""

import logging
import re
import shutil
import zipfile
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

import pydicom
from fastapi import UploadFile
from pydicom.errors import InvalidDicomError
from pydicom.multival import MultiValue

from app.core import errors
from app.models.study import Modality, SeriesRecord, StudyRecord
from app.services.storage import StudyStorage, new_id

logger = logging.getLogger(__name__)

_CHUNK = 1024 * 1024
_DICOMDIR_SOP_CLASS = "1.2.840.10008.1.3.10"


# -- upload --------------------------------------------------------------------


class _ByteBudget:
    def __init__(self, limit: int) -> None:
        self.limit = limit
        self.used = 0

    def consume(self, n: int) -> None:
        self.used += n
        if self.used > self.limit:
            raise errors.upload_too_large(self.limit // (1024 * 1024))


def _safe_name(name: str | None) -> str:
    """The last part of an uploaded file name, reduced to safe characters.

    Kept on disk (after a random id) because NIfTI files carry their modality in the name. It is never
    logged, and the upload directory is deleted after the upload is processed.
    """
    return re.sub(r"[^A-Za-z0-9._-]", "_", Path(name or "").name)[-64:]


async def save_uploads(files: list[UploadFile], dest: Path, max_bytes: int) -> list[Path]:
    """Stream uploaded files to `dest`, enforcing a total size limit."""
    budget = _ByteBudget(max_bytes)
    saved: list[Path] = []
    for upload in files:
        path = dest / f"{new_id()}_{_safe_name(upload.filename)}"
        with path.open("wb") as out:
            while chunk := await upload.read(_CHUNK):
                budget.consume(len(chunk))
                out.write(chunk)
        await upload.close()
        saved.append(path)
    return saved


def expand_archives(paths: list[Path], dest: Path, max_bytes: int, max_members: int = 10000) -> list[Path]:
    """Replace any zip archives in `paths` with their extracted members."""
    budget = _ByteBudget(max_bytes)
    result: list[Path] = []
    for path in paths:
        if not zipfile.is_zipfile(path):
            result.append(path)
            continue
        try:
            with zipfile.ZipFile(path) as archive:
                members = archive.infolist()
                if len(members) > max_members:
                    raise errors.upload_too_large(max_bytes // (1024 * 1024))
                for member in members:
                    if member.is_dir():
                        continue
                    budget.consume(member.file_size)
                    target = dest / f"{new_id()}_{_safe_name(member.filename)}"
                    with archive.open(member) as src, target.open("wb") as out:
                        shutil.copyfileobj(src, out, _CHUNK)
                    result.append(target)
        except zipfile.BadZipFile as exc:
            raise errors.invalid_dicom() from exc
        path.unlink(missing_ok=True)
    return result


# -- validation ------------------------------------------------------------------


@dataclass
class DicomHeader:
    path: Path
    series_uid: str
    sop_uid: str
    dataset: pydicom.Dataset


def read_header(path: Path) -> DicomHeader | None:
    """Return the header of a valid MR image DICOM file, or None if the file is not usable."""
    try:
        ds = pydicom.dcmread(path, stop_before_pixels=True)
    except (InvalidDicomError, OSError, ValueError, EOFError, AttributeError, KeyError, TypeError):
        return None

    sop_class = str(getattr(getattr(ds, "file_meta", None), "MediaStorageSOPClassUID", ""))
    if sop_class == _DICOMDIR_SOP_CLASS:
        return None
    required = ("SeriesInstanceUID", "SOPInstanceUID", "Rows", "Columns")
    if any(not hasattr(ds, tag) for tag in required):
        return None
    if str(getattr(ds, "Modality", "MR")).upper() != "MR":
        return None
    return DicomHeader(path=path, series_uid=str(ds.SeriesInstanceUID), sop_uid=str(ds.SOPInstanceUID), dataset=ds)


# -- modality classification --------------------------------------------------------


def _text(ds: pydicom.Dataset) -> str:
    parts = (getattr(ds, name, "") for name in ("SeriesDescription", "ProtocolName", "SequenceName"))
    return " ".join(str(p) for p in parts).upper()


def _image_type(ds: pydicom.Dataset) -> list[str]:
    value = getattr(ds, "ImageType", [])
    if isinstance(value, str):
        value = value.split("\\")
    return [str(v).upper() for v in value]


def _b_value(ds: pydicom.Dataset) -> float | None:
    for tag in ((0x0018, 0x9087), (0x0043, 0x1039), (0x0019, 0x100C)):  # standard, GE, Siemens
        if tag in ds:
            try:
                raw = ds[tag].value
                if isinstance(raw, (bytes, bytearray)):
                    raw = raw.decode(errors="ignore").split("\\")[0]
                if isinstance(raw, (list, tuple, MultiValue)):
                    raw = raw[0]
                return float(raw)
            except (TypeError, ValueError, IndexError):
                continue
    return None


def classify_modality(ds: pydicom.Dataset) -> Modality:
    """Heuristic prostate MRI sequence classification from DICOM headers."""
    text = _text(ds)
    image_type = _image_type(ds)

    if "ADC" in image_type or "ADC" in text or "APPARENT DIFFUSION" in text:
        return Modality.ADC
    if (
        "DIFFUSION" in image_type
        or any(k in text for k in ("DWI", "DIFFUSION", "TRACEW", "EP2D_DIFF", "B-VALUE", "B1000", "B800"))
        or (_b_value(ds) or 0) > 0
    ):
        return Modality.DWI
    if "T2" in text and "T2*" not in text:
        return Modality.T2W
    try:
        te = float(getattr(ds, "EchoTime", 0) or 0)
        tr = float(getattr(ds, "RepetitionTime", 0) or 0)
    except (TypeError, ValueError):
        te = tr = 0
    if te >= 80 and tr >= 2000:
        return Modality.T2W
    return Modality.UNKNOWN


# -- grouping ----------------------------------------------------------------------


@dataclass
class _SeriesGroup:
    headers: list[DicomHeader] = field(default_factory=list)
    sop_uids: set[str] = field(default_factory=set)


def group_into_series(study: StudyRecord, paths: Iterable[Path], storage: StudyStorage) -> StudyRecord:
    """Validate files, group them by SeriesInstanceUID and move them into per-series directories."""
    groups: dict[str, _SeriesGroup] = {}
    total = skipped = 0

    for path in paths:
        total += 1
        header = read_header(path)
        if header is None:
            skipped += 1
            path.unlink(missing_ok=True)
            continue
        group = groups.setdefault(header.series_uid, _SeriesGroup())
        if header.sop_uid in group.sop_uids:  # duplicate instance
            skipped += 1
            path.unlink(missing_ok=True)
            continue
        group.sop_uids.add(header.sop_uid)
        group.headers.append(header)

    if total == 0:
        raise errors.no_dicom_found()
    if not groups:
        raise errors.invalid_dicom()

    dicom_dir = storage.dicom_dir(study.study_id)
    series: list[SeriesRecord] = []
    for index, group in enumerate(groups.values()):
        dir_name = f"{index:03d}"
        series_dir = dicom_dir / dir_name
        series_dir.mkdir(parents=True, exist_ok=True)
        for i, header in enumerate(group.headers):
            header.path.replace(series_dir / f"{i:05d}.dcm")
        first = group.headers[0].dataset
        description = getattr(first, "SeriesDescription", None)
        series.append(
            SeriesRecord(
                series_id=new_id(),
                modality=classify_modality(first),
                num_instances=len(group.headers),
                description=str(description) if description else None,
                dir_name=dir_name,
            )
        )

    study.series = series
    study.skipped_files = skipped
    logger.info("Study %s: %d series, %d files skipped", study.study_id, len(series), skipped)
    return study
