# src/model/job.py
from dataclasses import dataclass


@dataclass
class Job:
    id: str
    type: str
    user_id: int | None
    domain_code: str | None
    status: str
    engine_version: str | None
    result: str | None
    error_message: str | None
    request_id: str
    created_at: str
    updated_at: str
