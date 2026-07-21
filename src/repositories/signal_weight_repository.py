# src/repositories/signal_weight_repository.py
import logging

from src.core.db import get_connection

logger = logging.getLogger(__name__)


def get_all() -> dict[str, float]:
    conn = get_connection()
    try:
        rows = conn.execute("SELECT status, weight FROM signal_weights").fetchall()
        weights = {row["status"]: row["weight"] for row in rows}
        logger.debug(
            "pesos de señal cargados",
            extra={
                "layer": "repository",
                "event": "signal_weights_loaded",
                "count": len(weights),
            },
        )
        return weights
    finally:
        conn.close()
