"""MySQL tables (SQLAlchemy 2.0). Image and mask files stay on disk; these rows describe them.

Ids are server-generated 32-char hex strings. Datetimes are stored as naive UTC.
`create_all` builds the schema at startup.
ponytail: no Alembic yet; add migrations before the first schema change on a database that holds data.
"""

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.mysql import DATETIME as MYSQL_DATETIME
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

_ID = String(32)
# MySQL DATETIME drops fractional seconds by default, which would make "newest first" ambiguous.
_DT = DateTime().with_variant(MYSQL_DATETIME(fsp=6), "mysql")


class Base(DeclarativeBase):
    pass


class UserRow(Base):
    """An anonymous device user. Only a hash of its bearer token is stored."""

    __tablename__ = "users"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    created_at: Mapped[datetime] = mapped_column(_DT)


class StudyRow(Base):
    __tablename__ = "studies"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(16))
    skipped_files: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(_DT)
    updated_at: Mapped[datetime] = mapped_column(_DT, index=True)

    series: Mapped[list["SeriesRow"]] = relationship(
        back_populates="study", cascade="all, delete-orphan", order_by="SeriesRow.position"
    )
    nifti_files: Mapped[list["NiftiRow"]] = relationship(
        back_populates="study", cascade="all, delete-orphan", order_by="NiftiRow.position"
    )
    mask_versions: Mapped[list["MaskVersionRow"]] = relationship(
        back_populates="study", cascade="all, delete-orphan", order_by="MaskVersionRow.created_at"
    )
    jobs: Mapped[list["JobRow"]] = relationship(back_populates="study", cascade="all, delete-orphan")


class SeriesRow(Base):
    __tablename__ = "series"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    study_id: Mapped[str] = mapped_column(ForeignKey("studies.id"), index=True)
    position: Mapped[int] = mapped_column(Integer)
    modality: Mapped[str] = mapped_column(String(16))
    num_instances: Mapped[int] = mapped_column(Integer)
    description: Mapped[str | None] = mapped_column(String(255))
    dir_name: Mapped[str] = mapped_column(String(64))

    study: Mapped[StudyRow] = relationship(back_populates="series")


class NiftiRow(Base):
    __tablename__ = "nifti_files"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)  # the public resource_id
    study_id: Mapped[str] = mapped_column(ForeignKey("studies.id"), index=True)
    series_id: Mapped[str] = mapped_column(_ID)
    position: Mapped[int] = mapped_column(Integer)
    modality: Mapped[str] = mapped_column(String(16))
    shape: Mapped[list[int]] = mapped_column(JSON)
    voxel_spacing: Mapped[list[float]] = mapped_column(JSON)
    file_name: Mapped[str] = mapped_column(String(64))

    study: Mapped[StudyRow] = relationship(back_populates="nifti_files")


class MaskVersionRow(Base):
    """One version of a segmentation mask: the read-only AI output, or a later manual correction."""

    __tablename__ = "mask_versions"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)  # the public version / resource id
    study_id: Mapped[str] = mapped_column(ForeignKey("studies.id"), index=True)
    source: Mapped[str] = mapped_column(String(24))  # "ai" | "manual_correction"
    base_version_id: Mapped[str | None] = mapped_column(_ID)
    labels: Mapped[dict[str, str]] = mapped_column(JSON)
    volume_ml: Mapped[float] = mapped_column(Float)
    model_name: Mapped[str | None] = mapped_column(String(255))
    model_note: Mapped[str | None] = mapped_column(Text)
    file_name: Mapped[str] = mapped_column(String(64))
    read_only: Mapped[bool] = mapped_column(Boolean, default=True)
    edited_slices: Mapped[list[int]] = mapped_column(JSON, default=list)
    refined_slices: Mapped[list[int]] = mapped_column(JSON, default=list)
    created_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(_DT)

    study: Mapped[StudyRow] = relationship(back_populates="mask_versions")


class JobRow(Base):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(_ID, primary_key=True)
    study_id: Mapped[str] = mapped_column(ForeignKey("studies.id"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    kind: Mapped[str] = mapped_column(String(24))  # "segmentation"
    status: Mapped[str] = mapped_column(String(16), index=True)  # queued | running | completed | failed
    error_code: Mapped[str | None] = mapped_column(String(64))
    error_message: Mapped[str | None] = mapped_column(Text)
    mask_version_id: Mapped[str | None] = mapped_column(_ID)
    created_at: Mapped[datetime] = mapped_column(_DT)
    started_at: Mapped[datetime | None] = mapped_column(_DT)
    finished_at: Mapped[datetime | None] = mapped_column(_DT)

    study: Mapped[StudyRow] = relationship(back_populates="jobs")
