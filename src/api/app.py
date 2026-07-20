# src/api/app.py
from flask import Flask, g, jsonify, request

from src.api.routes.jobs_routes import jobs_bp
from src.core.db import init_db
from src.core.errors import AppError
from src.core.logging_config import configure_logging, get_request_id, set_request_id


def create_app() -> Flask:
    configure_logging()

    app = Flask(__name__)
    init_db()

    @app.before_request
    def _assign_request_id() -> None:
        incoming = request.headers.get("X-Request-Id")
        g.request_id = set_request_id(incoming)

    @app.after_request
    def _add_request_id_header(response):
        response.headers["X-Request-Id"] = get_request_id() or ""
        return response

    @app.errorhandler(AppError)
    def _handle_app_error(error: AppError):
        return jsonify(error.to_dict(get_request_id())), error.http_status

    app.register_blueprint(jobs_bp, url_prefix="/api/v1")

    return app
