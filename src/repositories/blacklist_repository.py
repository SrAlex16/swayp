# src/repositories/blacklist_repository.py
"""Blacklist dura (ver docs/ARCHITECTURE.md sección 3.3): exclusión permanente y
explícita de un ítem, distinta de ratings.status='rejected' — no es señal de
entrenamiento, no se usa para ponderar el perfil, solo para excluir candidatos."""

import logging

from src.core.db import get_connection

logger = logging.getLogger(__name__)


def add(user_id: int, item_id: int, domain_code: str) -> None:
    """Idempotente: si el par (user_id, item_id) ya está en la blacklist, no falla
    ni duplica — `INSERT OR IGNORE` sobre la PRIMARY KEY (user_id, item_id)."""
    conn = get_connection()
    try:
        conn.execute(
            """
            INSERT OR IGNORE INTO blacklist (user_id, item_id, domain_code)
            VALUES (?, ?, ?)
            """,
            (user_id, item_id, domain_code),
        )
        conn.commit()
        logger.debug(
            "item añadido a la blacklist",
            extra={
                "layer": "repository",
                "event": "blacklist_item_added",
                "user_id": user_id,
                "item_id": item_id,
                "domain_code": domain_code,
            },
        )
    finally:
        conn.close()


def get_item_ids(user_id: int, domain_code: str) -> set[int]:
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT item_id FROM blacklist WHERE user_id = ? AND domain_code = ?",
            (user_id, domain_code),
        ).fetchall()
        item_ids = {row["item_id"] for row in rows}
        logger.debug(
            "item_ids de blacklist cargados",
            extra={
                "layer": "repository",
                "event": "blacklist_loaded",
                "user_id": user_id,
                "domain_code": domain_code,
                "count": len(item_ids),
            },
        )
        return item_ids
    finally:
        conn.close()
