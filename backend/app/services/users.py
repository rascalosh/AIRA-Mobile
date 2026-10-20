"""Anonymous device users: the app registers once and keeps the bearer token on the device."""

import hashlib
import secrets

from sqlalchemy import select

from app.db.models import UserRow
from app.db.session import Database
from app.services.storage import StudyStorage, new_id, utc_now


def _hash(token: str) -> str:
    # The token is 256 random bits, so a plain SHA-256 is enough (no need for a slow password hash).
    return hashlib.sha256(token.encode()).hexdigest()


def create_anonymous(db: Database) -> tuple[str, str]:
    """Create a user and return (user_id, token). The token is shown once and never stored."""
    user_id, token = new_id(), secrets.token_urlsafe(32)
    with db.session() as session:
        session.add(UserRow(id=user_id, token_hash=_hash(token), created_at=utc_now()))
    return user_id, token


def authenticate(db: Database, token: str) -> str | None:
    """The user id for a bearer token, or None."""
    with db.session() as session:
        return session.scalar(select(UserRow.id).where(UserRow.token_hash == _hash(token)))


def delete_user(storage: StudyStorage, db: Database, user_id: str) -> None:
    """Delete the user's studies (rows and files) and then the user."""
    for study in storage.list_for_user(user_id):
        storage.delete(study.study_id, user_id)
    with db.session() as session:
        row = session.get(UserRow, user_id)
        if row is not None:
            session.delete(row)
