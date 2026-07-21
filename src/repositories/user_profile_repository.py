# src/repositories/user_profile_repository.py
import logging
import sqlite3

from src.core.db import get_connection
from src.model.user import UserProfile

logger = logging.getLogger(__name__)


def _row_to_profile(row: sqlite3.Row) -> UserProfile:
    return UserProfile(
        user_id=row["user_id"],
        age=row["age"],
        gender=row["gender"],
        updated_at=row["updated_at"],
    )


def get(user_id: int) -> UserProfile | None:
    conn = get_connection()
    try:
        row = conn.execute(
            "SELECT * FROM user_profile WHERE user_id = ?", (user_id,)
        ).fetchone()
        profile = _row_to_profile(row) if row is not None else None
        logger.debug(
            "perfil de usuario buscado",
            extra={
                "layer": "repository",
                "event": "user_profile_lookup",
                "user_id": user_id,
                "found": profile is not None,
            },
        )
        return profile
    finally:
        conn.close()


def upsert(user_id: int, age: int | None = None, gender: str | None = None) -> UserProfile:
    conn = get_connection()
    try:
        conn.execute(
            """
            INSERT INTO user_profile (user_id, age, gender)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                age = excluded.age,
                gender = excluded.gender,
                updated_at = CURRENT_TIMESTAMP
            """,
            (user_id, age, gender),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM user_profile WHERE user_id = ?", (user_id,)
        ).fetchone()
        profile = _row_to_profile(row)
        logger.debug(
            "perfil de usuario actualizado",
            extra={
                "layer": "repository",
                "event": "user_profile_upserted",
                "user_id": user_id,
            },
        )
        return profile
    finally:
        conn.close()
