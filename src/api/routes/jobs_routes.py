# src/api/routes/jobs_routes.py
import json
import logging

from flask import Blueprint, jsonify, request

from src.core.errors import NotFoundError, ValidationError
from src.core.logging_config import get_request_id
from src.repositories import job_repository, user_repository
from src.services import job_service

logger = logging.getLogger(__name__)

jobs_bp = Blueprint("jobs", __name__)


@jobs_bp.route("/domains/<domain_code>/recommendations/jobs", methods=["POST"])
def create_recommendation_job(domain_code: str):
    body = request.get_json(silent=True) or {}
    device_id = body.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")

    user = user_repository.get_or_create_by_device_id(device_id)
    job_id = job_service.create_and_run_recommendation_job(
        user_id=user.id, domain_code=domain_code, request_id=get_request_id()
    )

    logger.info(
        "job de recomendaciones solicitado",
        extra={
            "layer": "api",
            "event": "recommendation_job_requested",
            "job_id": job_id,
            "user_id": user.id,
            "domain_code": domain_code,
        },
    )

    return jsonify({"job_id": job_id}), 202


@jobs_bp.route("/jobs/<job_id>", methods=["GET"])
def get_job(job_id: str):
    # Sin log de negocio aquí a propósito: se sondea repetidamente (polling) mientras
    # un job está en curso y ya queda trazado por sus propios eventos
    # (job_started/job_done/job_failed en job_service).
    job = job_repository.get_by_id(job_id)
    if job is None:
        raise NotFoundError(f"Job {job_id} no encontrado")

    payload: dict = {"status": job.status}
    if job.result is not None:
        payload["result"] = json.loads(job.result)
    if job.error_message is not None:
        payload["error_message"] = job.error_message

    return jsonify(payload), 200
