from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.db.models import Base


class Database:
    """Engine + short-lived sessions. `url` is a SQLAlchemy URL: mysql+pymysql://... or sqlite:///..."""

    def __init__(self, url: str) -> None:
        kwargs: dict = {"pool_pre_ping": True}
        if url.startswith("sqlite"):
            kwargs["connect_args"] = {"check_same_thread": False}
        else:
            kwargs["pool_recycle"] = 3600  # MySQL closes idle connections
        self.engine = create_engine(url, **kwargs)
        self._sessions = sessionmaker(self.engine, expire_on_commit=False)

    @contextmanager
    def session(self) -> Iterator[Session]:
        """One transaction: commits on success, rolls back on error."""
        with self._sessions.begin() as session:
            yield session

    def create_all(self) -> None:
        Base.metadata.create_all(self.engine)
