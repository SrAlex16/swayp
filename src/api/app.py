# src/api/app.py
import logging
import time

from flask import Flask, g, jsonify, request
from werkzeug.exceptions import HTTPException

from src.api.routes.domains_routes import domains_bp
from src.api.routes.jobs_routes import jobs_bp
from src.api.routes.profile_routes import profile_bp
from src.api.routes.ratings_routes import ratings_bp
from src.api.routes.seed_routes import seed_bp
from src.core.db import init_db
from src.core.errors import AppError
from src.core.logging_config import configure_logging, get_request_id, set_request_id

logger = logging.getLogger(__name__)


def _elapsed_ms() -> float | None:
    start_time = g.get("start_time")
    if start_time is None:
        return None
    return round((time.monotonic() - start_time) * 1000, 2)


def create_app() -> Flask:
    configure_logging()

    app = Flask(__name__)
    init_db()

    @app.before_request
    def _assign_request_id() -> None:
        incoming = request.headers.get("X-Request-Id")
        g.request_id = set_request_id(incoming)
        g.start_time = time.monotonic()

    @app.after_request
    def _finalize_response(response):
        # Se ejecuta para toda request que llegue a completarse con una respuesta —
        # éxito o error controlado vía AppError incluidos — sin depender de que cada
        # ruta loguee su propio evento de negocio. Para el camino de excepción no
        # controlada, ver el comentario en _handle_unexpected_error más abajo.
        response.headers["X-Request-Id"] = get_request_id() or ""
        logger.info(
            "request completada",
            extra={
                "layer": "api",
                "event": "request_completed",
                "method": request.method,
                "path": request.path,
                "status_code": response.status_code,
                "duration_ms": _elapsed_ms(),
            },
        )
        return response

    @app.errorhandler(AppError)
    def _handle_app_error(error: AppError):
        logger.warning(
            "request fallida",
            extra={
                "layer": "api",
                "event": "app_error",
                "error_code": error.error_code,
                "http_status": error.http_status,
                "path": request.path,
                "method": request.method,
            },
        )
        return jsonify(error.to_dict(get_request_id())), error.http_status

    @app.errorhandler(Exception)
    def _handle_unexpected_error(error: Exception):
        # Deja pasar los errores HTTP normales de Flask (404 de ruta no encontrada,
        # 405 método no permitido...) con su respuesta por defecto; solo se envuelven
        # las excepciones realmente no controladas, para que nunca escape una traza
        # cruda ni una respuesta que no sea nuestro JSON estándar de error.
        if isinstance(error, HTTPException):
            return error

        # En Flask, una respuesta devuelta por un errorhandler (incluido este) sigue
        # pasando por after_request (confirmado con el test client, ver ronda de
        # prueba) — así que _finalize_response también logueará request_completed
        # para este camino. Aun así, se añaden duration_ms/status_code aquí también:
        # es la única línea que lleva el traceback completo (exc_info=True), y
        # conviene poder ver cuánto tardó en fallar sin tener que cruzarla con la
        # línea de request_completed correspondiente.
        logger.error(
            "excepción no controlada",
            extra={
                "layer": "api",
                "event": "unhandled_exception",
                "path": request.path,
                "method": request.method,
                "status_code": 500,
                "duration_ms": _elapsed_ms(),
            },
            exc_info=True,
        )
        fallback = AppError("Error interno inesperado")
        return jsonify(fallback.to_dict(get_request_id())), fallback.http_status

    app.register_blueprint(domains_bp, url_prefix="/api/v1")
    app.register_blueprint(jobs_bp, url_prefix="/api/v1")
    app.register_blueprint(profile_bp, url_prefix="/api/v1")
    app.register_blueprint(ratings_bp, url_prefix="/api/v1")
    app.register_blueprint(seed_bp, url_prefix="/api/v1")

    return app
