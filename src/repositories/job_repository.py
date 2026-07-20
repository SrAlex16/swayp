# src/repositories/job_repository.py
import logging
import sqlite3

from src.core.db import get_connection
from src.model.job import Job

logger = logging.getLogger(__name__)


def _row_to_job(row: sqlite3.Row) -> Job:
    return Job(
        id=row["id"],
        type=row["type"],
        user_id=row["user_id"],
        domain_code=row["domain_code"],
        status=row["status"],
        engine_version=row["engine_version"],
        result=row["result"],
        error_message=row["error_message"],
        request_id=row["request_id"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def create(
    job_id: str,
    type: str,
    user_id: int | None,
    domain_code: str | None,
    request_id: str,
) -> Job:
    conn = get_connection()
    try:
        conn.execute(
            """
            INSERT INTO jobs (id, type, user_id, domain_code, status, request_id)
            VALUES (?, ?, ?, ?, 'pending', ?)
            """,
            (job_id, type, user_id, domain_code, request_id),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        job = _row_to_job(row)
        logger.debug(
            "job creado",
            extra={
                "layer": "repository",
                "event": "job_created",
                "job_id": job_id,
                "type": type,
                "user_id": user_id,
                "domain_code": domain_code,
            },
        )
        return job
    finally:
        conn.close()


def update_status(
    job_id: str,
    status: str,
    result: str | None = None,
    error_message: str | None = None,
    engine_version: str | None = None,
) -> None:
    conn = get_connection()
    try:
        conn.execute(
            """
            UPDATE jobs
            SET status = ?,
                result = COALESCE(?, result),
                error_message = COALESCE(?, error_message),
                engine_version = COALESCE(?, engine_version),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (status, result, error_message, engine_version, job_id),
        )
        conn.commit()
        logger.debug(
            "job actualizado",
            extra={
                "layer": "repository",
                "event": "job_status_updated",
                "job_id": job_id,
                "status": status,
            },
        )
    finally:
        conn.close()


def get_by_id(job_id: str) -> Job | None:
    conn = get_connection()
    try:
        row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
        return _row_to_job(row) if row is not None else None
    finally:
        conn.close()
