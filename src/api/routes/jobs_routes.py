# src/api/routes/jobs_routes.py
import json

from flask import Blueprint, jsonify, request

from src.core.errors import NotFoundError, ValidationError
from src.core.logging_config import get_request_id
from src.repositories import job_repository, user_repository
from src.services import job_service

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

    return jsonify({"job_id": job_id}), 202


@jobs_bp.route("/jobs/<job_id>", methods=["GET"])
def get_job(job_id: str):
    job = job_repository.get_by_id(job_id)
    if job is None:
        raise NotFoundError(f"Job {job_id} no encontrado")

    payload: dict = {"status": job.status}
    if job.result is not None:
        payload["result"] = json.loads(job.result)
    if job.error_message is not None:
        payload["error_message"] = job.error_message

    return jsonify(payload), 200
