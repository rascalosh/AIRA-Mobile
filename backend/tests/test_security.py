"""Abuse limits, quotas, headers, and erasing a user's data."""

import io
import zipfile

import pytest
from fastapi.testclient import TestClient

from app.core import errors
from app.core.config import Settings
from app.core.ratelimit import RateLimiter
from app.main import create_app
from tests.conftest import as_upload, register


def test_rate_limiter_counts_per_key_and_recovers() -> None:
    now = [0.0]
    limiter = RateLimiter(clock=lambda: now[0])
    limiter.check("a", 2, 10)
    limiter.check("a", 2, 10)
    with pytest.raises(errors.AppError) as exc:
        limiter.check("a", 2, 10)
    assert exc.value.status_code == 429 and exc.value.headers["Retry-After"]
    limiter.check("b", 2, 10)  # other keys are unaffected
    now[0] = 11.0
    limiter.check("a", 2, 10)  # the window has passed


def test_registration_is_rate_limited(settings: Settings) -> None:
    settings.rate_limit_register = 3
    with TestClient(create_app(settings)) as c:
        codes = [c.post("/api/v1/users/anonymous").status_code for _ in range(5)]
    assert codes == [201, 201, 201, 429, 429]


def test_upload_is_rate_limited_per_user(client: TestClient, other_client: TestClient, settings: Settings, t2w_series) -> None:
    settings.rate_limit_upload = 1
    first = client.post("/api/v1/studies/upload", files=as_upload(t2w_series))
    second = client.post("/api/v1/studies/upload", files=as_upload(t2w_series))
    assert (first.status_code, second.status_code) == (201, 429)
    assert second.json()["error"]["code"] == "TOO_MANY_REQUESTS"
    assert other_client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).status_code == 201


def test_study_quota(client: TestClient, settings: Settings, t2w_series) -> None:
    settings.max_studies_per_user = 1
    assert client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).status_code == 201
    over = client.post("/api/v1/studies/upload", files=as_upload(t2w_series))
    assert over.status_code == 429 and over.json()["error"]["code"] == "QUOTA_EXCEEDED"


def test_too_many_files_and_zip_members(client: TestClient, settings: Settings, t2w_series) -> None:
    settings.max_upload_files = 2
    assert client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).status_code == 429

    settings.max_upload_files, settings.max_zip_members = 100, 3
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for i in range(5):
            archive.writestr(f"f{i}.dcm", b"x")
    response = client.post("/api/v1/studies/upload", files=[("files", ("a.zip", buffer.getvalue(), "application/zip"))])
    assert response.status_code == 413


def test_responses_are_not_cacheable_and_have_security_headers(client: TestClient) -> None:
    headers = client.get("/health").headers
    assert headers["cache-control"] == "no-store"
    assert headers["x-content-type-options"] == "nosniff"
    assert headers["x-frame-options"] == "DENY"


def test_docs_and_cors_are_off_by_default(client: TestClient) -> None:
    assert client.get("/docs").status_code == 404
    assert client.get("/openapi.json").status_code == 404
    reply = client.options(
        "/api/v1/studies", headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"}
    )
    assert "access-control-allow-origin" not in reply.headers


def test_docs_can_be_enabled(settings: Settings) -> None:
    settings.docs_enabled = True
    with TestClient(create_app(settings)) as c:
        assert c.get("/openapi.json").status_code == 200


def test_delete_me_erases_studies_files_and_token(client: TestClient, settings: Settings, t2w_series) -> None:
    study_id = client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).json()["study_id"]
    client.post(f"/api/v1/studies/{study_id}/convert")
    assert (settings.storage_dir / study_id).exists()

    assert client.delete("/api/v1/users/me").status_code == 204
    assert not (settings.storage_dir / study_id).exists()
    assert client.get("/api/v1/studies").status_code == 401  # the token no longer works


def test_delete_me_leaves_other_users_alone(client: TestClient, other_client: TestClient, t2w_series) -> None:
    mine = client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).json()["study_id"]
    theirs = other_client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).json()["study_id"]
    client.delete("/api/v1/users/me")
    assert other_client.get(f"/api/v1/studies/{theirs}").status_code == 200
    assert mine != theirs


def test_segmentation_job_cap_per_user(tmp_path) -> None:
    from tests.test_segmentation_api import ALL_THREE, _upload_convert

    # The model file is missing, so jobs end quickly; the cap is checked while one is still active, so hold the
    # worker with an already-queued row instead of racing the real job.
    settings = Settings(storage_dir=tmp_path / "s", model_path=tmp_path / "none.pth", max_active_jobs_per_user=1, _env_file=None)
    with TestClient(create_app(settings)) as c:
        user_id = register(c)
        first = _upload_convert(c, tmp_path / "a", ALL_THREE)
        second = _upload_convert(c, tmp_path / "b", ALL_THREE)

        from app.db.models import JobRow
        from app.services.storage import new_id, utc_now

        with c.app.state.db.session() as session:
            session.add(JobRow(id=new_id(), study_id=first, user_id=user_id, kind="segmentation", status="running", created_at=utc_now()))
        over = c.post(f"/api/v1/studies/{second}/segment")

    assert over.status_code == 429 and over.json()["error"]["code"] == "QUOTA_EXCEEDED"
