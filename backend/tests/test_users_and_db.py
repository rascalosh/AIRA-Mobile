"""Users, ownership, persistence and cleanup, backed by the database."""

from datetime import timedelta

from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.core.config import Settings
from app.db.models import JobRow, MaskVersionRow, NiftiRow, SeriesRow, StudyRow, UserRow
from app.main import create_app
from app.services.storage import new_id, utc_now
from tests.conftest import as_upload


def _study(client, t2w_series) -> str:
    return client.post("/api/v1/studies/upload", files=as_upload(t2w_series)).json()["study_id"]


def _count(client, model) -> int:
    with client.app.state.db.session() as s:
        return s.scalar(select(func.count()).select_from(model))


def _running_job(client, study_id: str) -> str:
    job_id = new_id()
    user_id = client.app.state.storage.get(study_id).user_id
    with client.app.state.db.session() as s:
        s.add(
            JobRow(id=job_id, study_id=study_id, user_id=user_id, kind="segmentation", status="running", created_at=utc_now())
        )
    return job_id


def test_anonymous_users_are_distinct_and_tokens_are_not_stored(client):
    a = client.post("/api/v1/users/anonymous").json()
    b = client.post("/api/v1/users/anonymous").json()
    assert a["user_id"] != b["user_id"] and a["token"] != b["token"]
    with client.app.state.db.session() as s:
        hashes = set(s.scalars(select(UserRow.token_hash)))
    assert a["token"] not in hashes and all(len(h) == 64 for h in hashes)


def test_every_data_endpoint_requires_a_valid_token(client, t2w_series):
    study_id = _study(client, t2w_series)
    anonymous = TestClient(client.app)
    bad = TestClient(client.app, headers={"Authorization": "Bearer not-a-real-token"})
    for caller in (anonymous, bad):
        assert caller.get("/api/v1/studies").status_code == 401
        assert caller.get(f"/api/v1/studies/{study_id}").status_code == 401
        assert caller.post("/api/v1/studies/upload", files=as_upload(t2w_series)).status_code == 401
        assert caller.post(f"/api/v1/studies/{study_id}/segment").status_code == 401
        assert caller.get("/api/v1/jobs/" + "0" * 32).status_code == 401
        assert caller.get("/api/v1/resources/" + "0" * 32).status_code == 401
    assert anonymous.get("/health").status_code == 200
    assert anonymous.get("/api/v1/studies").json()["error"]["code"] == "UNAUTHORIZED"


def test_a_user_cannot_see_touch_or_download_another_users_study(client, other_client, t2w_series):
    study_id = _study(client, t2w_series)
    client.post(f"/api/v1/studies/{study_id}/convert")
    resource_id = client.get(f"/api/v1/studies/{study_id}").json()["nifti_files"][0]["resource_id"]

    assert other_client.get(f"/api/v1/studies/{study_id}").status_code == 404
    assert other_client.post(f"/api/v1/studies/{study_id}/convert").status_code == 404
    assert other_client.post(f"/api/v1/studies/{study_id}/segment").status_code == 404
    assert other_client.delete(f"/api/v1/studies/{study_id}").status_code == 404
    assert other_client.get(f"/api/v1/studies/{study_id}/mask/versions").status_code == 404
    assert other_client.get(f"/api/v1/resources/{resource_id}").status_code == 404
    assert other_client.get(f"/api/v1/resources/{resource_id}/slices/0").status_code == 404
    assert other_client.get("/api/v1/studies").json() == []

    # The owner is unaffected.
    assert client.get(f"/api/v1/studies/{study_id}").status_code == 200


def test_a_user_cannot_read_another_users_job(client, other_client, t2w_series):
    study_id = _study(client, t2w_series)
    job_id = _running_job(client, study_id)

    assert client.get(f"/api/v1/jobs/{job_id}").status_code == 200
    assert other_client.get(f"/api/v1/jobs/{job_id}").status_code == 404


def test_list_returns_own_studies_newest_first(client, t2w_series):
    first, second = _study(client, t2w_series), _study(client, t2w_series)
    assert [s["study_id"] for s in client.get("/api/v1/studies").json()] == [second, first]


def test_studies_survive_an_app_restart(settings: Settings, t2w_series):
    with TestClient(create_app(settings)) as first:
        token = first.post("/api/v1/users/anonymous").json()["token"]
        first.headers["Authorization"] = f"Bearer {token}"
        study_id = _study(first, t2w_series)
        first.post(f"/api/v1/studies/{study_id}/convert")

    with TestClient(create_app(settings), headers={"Authorization": f"Bearer {token}"}) as second:
        study = second.get(f"/api/v1/studies/{study_id}").json()
        assert study["status"] == "converted" and study["nifti_files"][0]["modality"] == "T2W"


def test_delete_removes_rows_and_files(client, settings, t2w_series):
    study_id = _study(client, t2w_series)
    client.post(f"/api/v1/studies/{study_id}/convert")
    assert client.delete(f"/api/v1/studies/{study_id}").status_code == 204

    assert client.get(f"/api/v1/studies/{study_id}").status_code == 404
    assert not (settings.storage_dir / study_id).exists()
    assert [_count(client, m) for m in (StudyRow, SeriesRow, NiftiRow, MaskVersionRow, JobRow)] == [0] * 5


def test_cannot_delete_a_study_with_a_running_job(client, t2w_series):
    study_id = _study(client, t2w_series)
    _running_job(client, study_id)

    response = client.delete(f"/api/v1/studies/{study_id}")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "INVALID_STATE"


def test_cleanup_deletes_expired_studies_but_not_ones_with_a_running_job(client, settings, t2w_series):
    old, busy, fresh = (_study(client, t2w_series) for _ in range(3))
    _running_job(client, busy)
    with client.app.state.db.session() as s:
        for study_id in (old, busy):
            s.get(StudyRow, study_id).updated_at = utc_now() - timedelta(hours=48)

    assert client.app.state.storage.cleanup_expired() == 1

    assert client.get(f"/api/v1/studies/{old}").status_code == 404
    assert not (settings.storage_dir / old).exists()
    assert client.get(f"/api/v1/studies/{busy}").status_code == 200
    assert client.get(f"/api/v1/studies/{fresh}").status_code == 200


def test_interrupted_jobs_are_failed_on_startup(client, t2w_series):
    study_id = _study(client, t2w_series)
    job_id = _running_job(client, study_id)

    assert client.app.state.jobs.fail_interrupted() == 1

    job = client.get(f"/api/v1/jobs/{job_id}").json()
    assert job["status"] == "failed" and job["error"]["code"] == "JOB_INTERRUPTED"
    assert client.delete(f"/api/v1/studies/{study_id}").status_code == 204  # no longer "active"
