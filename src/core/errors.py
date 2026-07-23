# src/core/errors.py
"""Jerarquía de excepciones de la app (ver docs/ARCHITECTURE.md, sección 3.4): cada una
mapea a un código HTTP y un error.code fijo, para que la respuesta JSON estandarizada
sea consistente en todos los endpoints: {"error": {"code", "message", "request_id"}}."""


class AppError(Exception):
    http_status: int = 500
    error_code: str = "INTERNAL_ERROR"

    def __init__(self, message: str | None = None):
        self.message = message or self.error_code
        super().__init__(self.message)

    def to_dict(self, request_id: str | None = None) -> dict:
        return {
            "error": {
                "code": self.error_code,
                "message": self.message,
                "request_id": request_id,
            }
        }


class ExternalApiError(AppError):
    http_status = 502
    error_code = "EXTERNAL_API_ERROR"


class NotFoundError(AppError):
    http_status = 404
    error_code = "NOT_FOUND"


class ValidationError(AppError):
    http_status = 400
    error_code = "VALIDATION_ERROR"


class JobFailedError(AppError):
    http_status = 500
    error_code = "JOB_FAILED"


class ConflictError(AppError):
    http_status = 409
    error_code = "CONFLICT"
