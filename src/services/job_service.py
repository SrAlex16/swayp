# src/services/job_service.py
"""Jobs asíncronos (ver docs/ARCHITECTURE.md, sección 3.5): un hilo en background es
suficiente para el alcance de este proyecto, no hace falta Celery/Redis. Resuelve el
timeout de 5 min del proyecto original (`get_recommendations_for_user.py` corriendo
síncrono dentro de la request)."""
import json
import logging
import threading
import uuid

from src.core.errors import AppError
from src.core.logging_config import set_request_id
from src.model.tfidf_engine import TFIDFRecommendationEngine
from src.repositories import job_repository
from src.services import recommendation_service

logger = logging.getLogger(__name__)

JOB_TYPE_GENERATE_RECOMMENDATIONS = "generate_recommendations"


def create_and_run_recommendation_job(user_id: int, domain_code: str, request_id: str) -> str:
    job_id = str(uuid.uuid4())
    job_repository.create(
        job_id=job_id,
        type=JOB_TYPE_GENERATE_RECOMMENDATIONS,
        user_id=user_id,
        domain_code=domain_code,
        request_id=request_id,
    )

    thread = threading.Thread(
        target=_run_recommendation_job,
        args=(job_id, user_id, domain_code, request_id),
        daemon=True,
    )
    thread.start()

    return job_id


def _run_recommendation_job(job_id: str, user_id: int, domain_code: str, request_id: str) -> None:
    # Un hilo nuevo no hereda el contextvar de request_id del hilo que lo lanzó (cada
    # hilo arranca con su propio contexto) — se fija explícitamente para que los logs
    # de este job queden trazables al mismo request_id que la request HTTP original.
    set_request_id(request_id)

    try:
        job_repository.update_status(job_id, "running")
        logger.info(
            "job de recomendaciones iniciado",
            extra={"layer": "service", "event": "job_started", "job_id": job_id},
        )

        results = recommendation_service.generate_recommendations(user_id, domain_code)

        job_repository.update_status(
            job_id,
            "done",
            result=json.dumps(results, ensure_ascii=False),
            engine_version=TFIDFRecommendationEngine.ENGINE_VERSION,
        )
        logger.info(
            "job de recomendaciones completado",
            extra={
                "layer": "service",
                "event": "job_done",
                "job_id": job_id,
                "count": len(results),
            },
        )
    except AppError as exc:
        job_repository.update_status(job_id, "error", error_message=exc.message)
        logger.error(
            "job de recomendaciones falló",
            extra={"layer": "service", "event": "job_failed", "job_id": job_id},
            exc_info=True,
        )
    except Exception as exc:  # nunca dejar el hilo morir sin registrar el estado
        job_repository.update_status(job_id, "error", error_message=str(exc))
        logger.error(
            "job de recomendaciones falló con una excepción inesperada",
            extra={"layer": "service", "event": "job_failed", "job_id": job_id},
            exc_info=True,
        )
