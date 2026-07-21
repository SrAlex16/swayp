# src/repositories/domain_repository.py
"""Solo conoce la tabla `domains`: qué dominios existen como concepto de producto. No
importa nada de src/adapters/ — no sabe qué clase de Python implementa cada dominio
(eso vive en src/adapters/registry.py, una capa de código, no de datos)."""
import logging
import sqlite3

from src.core.db import get_connection
from src.model.domain import Domain

logger = logging.getLogger(__name__)


def _row_to_domain(row: sqlite3.Row) -> Domain:
    return Domain(code=row["code"], display_name=row["display_name"], enabled=bool(row["enabled"]))


def get_enabled() -> list[Domain]:
    conn = get_connection()
    try:
        rows = conn.execute("SELECT * FROM domains WHERE enabled = 1").fetchall()
        domains = [_row_to_domain(row) for row in rows]
        logger.debug(
            "dominios habilitados cargados",
            extra={"layer": "repository", "event": "domains_loaded", "count": len(domains)},
        )
        return domains
    finally:
        conn.close()
