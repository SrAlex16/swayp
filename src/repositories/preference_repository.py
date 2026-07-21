# src/repositories/preference_repository.py
import logging

from src.core.db import get_connection

logger = logging.getLogger(__name__)


def get_by_domain(user_id: int, domain_code: str) -> list[tuple[str, float]]:
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT tag, weight FROM user_explicit_preferences WHERE user_id = ? AND domain_code = ?",
            (user_id, domain_code),
        ).fetchall()
        preferences = [(row["tag"], row["weight"]) for row in rows]
        logger.debug(
            "preferencias explícitas cargadas",
            extra={
                "layer": "repository",
                "event": "preferences_loaded",
                "user_id": user_id,
                "domain_code": domain_code,
                "count": len(preferences),
            },
        )
        return preferences
    finally:
        conn.close()


def set_preferences(user_id: int, domain_code: str, preferences: list[tuple[str, float]]) -> None:
    """Reemplaza todas las preferencias de user_id+domain_code por `preferences`:
    borra las que ya no estén en la lista, inserta/actualiza el resto."""
    conn = get_connection()
    try:
        new_tags = [tag for tag, _ in preferences]
        if new_tags:
            placeholders = ",".join("?" for _ in new_tags)
            conn.execute(
                f"""
                DELETE FROM user_explicit_preferences
                WHERE user_id = ? AND domain_code = ? AND tag NOT IN ({placeholders})
                """,
                (user_id, domain_code, *new_tags),
            )
        else:
            conn.execute(
                "DELETE FROM user_explicit_preferences WHERE user_id = ? AND domain_code = ?",
                (user_id, domain_code),
            )

        for tag, weight in preferences:
            conn.execute(
                """
                INSERT INTO user_explicit_preferences (user_id, domain_code, tag, weight)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(user_id, domain_code, tag) DO UPDATE SET weight = excluded.weight
                """,
                (user_id, domain_code, tag, weight),
            )

        conn.commit()
        logger.debug(
            "preferencias explícitas reemplazadas",
            extra={
                "layer": "repository",
                "event": "preferences_set",
                "user_id": user_id,
                "domain_code": domain_code,
                "count": len(preferences),
            },
        )
    finally:
        conn.close()
