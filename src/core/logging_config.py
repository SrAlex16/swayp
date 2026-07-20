# src/core/logging_config.py
"""Logging estructurado en JSON (ver docs/ARCHITECTURE.md, sección 3.6): un log por
línea, con request_id propagado vía contextvars en vez de pasarlo explícitamente por
cada función."""
import contextvars
import json
import logging
import uuid
from datetime import datetime, timezone

from src.core.config import config

_request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id", default=None
)

# Atributos propios de logging.LogRecord: cualquier otra clave que llegue vía el
# kwarg `extra=` de una llamada de log se trata como dato de negocio y va al campo
# "extra" del JSON de salida (salvo "layer"/"event", que se promocionan a top-level).
_RESERVED_RECORD_ATTRS = frozenset(
    logging.LogRecord("", 0, "", 0, "", (), None).__dict__.keys()
) | {"message", "asctime", "taskName"}


def new_request_id() -> str:
    """Genera un request_id nuevo (uuid4 hex corto)."""
    return uuid.uuid4().hex[:12]


def set_request_id(request_id: str | None = None) -> str:
    """Fija el request_id del contexto actual, generando uno si no se pasa."""
    value = request_id or new_request_id()
    _request_id_var.set(value)
    return value


def get_request_id() -> str | None:
    return _request_id_var.get()


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        extra = {
            key: value
            for key, value in record.__dict__.items()
            if key not in _RESERVED_RECORD_ATTRS and key not in {"layer", "event"}
        }

        payload = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "request_id": get_request_id(),
            "layer": getattr(record, "layer", record.name),
            "event": getattr(record, "event", None),
            "message": record.getMessage(),
        }
        if extra:
            payload["extra"] = extra
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)

        return json.dumps(payload, ensure_ascii=False)


def configure_logging() -> None:
    """Configura el root logger para emitir JSON estructurado, un log por línea."""
    handler = logging.StreamHandler()
    handler.setFormatter(JSONFormatter())

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(config.log_level)
