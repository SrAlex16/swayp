# tests/repositories/test_job_repository.py
from src.repositories import job_repository


def test_create_status_inicial_pending(temp_db):
    job = job_repository.create(
        job_id="job-1", type="generate_recommendations", user_id=None, domain_code="games", request_id="req-1"
    )

    assert job.id == "job-1"
    assert job.status == "pending"
    assert job.result is None
    assert job.error_message is None
    assert job.engine_version is None


def test_update_status_coalesce_preserva_campos_no_pasados(temp_db):
    job_repository.create(
        job_id="job-1", type="generate_recommendations", user_id=None, domain_code="games", request_id="req-1"
    )

    job_repository.update_status("job-1", "running")
    running = job_repository.get_by_id("job-1")
    assert running.status == "running"
    assert running.result is None
    assert running.engine_version is None

    job_repository.update_status("job-1", "done", result='{"ok": true}', engine_version="tfidf-0.1")
    done = job_repository.get_by_id("job-1")
    assert done.status == "done"
    assert done.result == '{"ok": true}'
    assert done.engine_version == "tfidf-0.1"
    assert done.error_message is None

    # Una tercera actualización sin pasar result/engine_version no debe borrarlos
    # (COALESCE conserva el valor previo cuando el nuevo es None).
    job_repository.update_status("job-1", "done")
    still_done = job_repository.get_by_id("job-1")
    assert still_done.result == '{"ok": true}'
    assert still_done.engine_version == "tfidf-0.1"


def test_get_by_id_inexistente_devuelve_none(temp_db):
    assert job_repository.get_by_id("no-existe") is None
