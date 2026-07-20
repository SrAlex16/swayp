# src/repositories/user_repository.py
import sqlite3

from src.core.db import get_connection
from src.model.user import User


def _row_to_user(row: sqlite3.Row) -> User:
    return User(id=row["id"], device_id=row["device_id"], created_at=row["created_at"])


def get_or_create_by_device_id(device_id: str) -> User:
    conn = get_connection()
    try:
        row = conn.execute(
            "SELECT * FROM users WHERE device_id = ?", (device_id,)
        ).fetchone()

        if row is None:
            conn.execute("INSERT INTO users (device_id) VALUES (?)", (device_id,))
            conn.commit()
            row = conn.execute(
                "SELECT * FROM users WHERE device_id = ?", (device_id,)
            ).fetchone()

        return _row_to_user(row)
    finally:
        conn.close()
