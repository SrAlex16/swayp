# src/repositories/rating_repository.py
import sqlite3

from src.core.db import get_connection
from src.model.rating import Rating


def _row_to_rating(row: sqlite3.Row) -> Rating:
    return Rating(
        id=row["id"],
        user_id=row["user_id"],
        item_id=row["item_id"],
        domain_code=row["domain_code"],
        status=row["status"],
        source=row["source"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
    )


def create(user_id: int, item_id: int, domain_code: str, status: str, source: str) -> Rating:
    conn = get_connection()
    try:
        cursor = conn.execute(
            """
            INSERT INTO ratings (user_id, item_id, domain_code, status, source)
            VALUES (?, ?, ?, ?, ?)
            """,
            (user_id, item_id, domain_code, status, source),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM ratings WHERE id = ?", (cursor.lastrowid,)
        ).fetchone()
        return _row_to_rating(row)
    finally:
        conn.close()


def get_by_user(user_id: int, domain_code: str) -> list[Rating]:
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM ratings WHERE user_id = ? AND domain_code = ?",
            (user_id, domain_code),
        ).fetchall()
        return [_row_to_rating(row) for row in rows]
    finally:
        conn.close()
