# src/repositories/rating_repository.py
import logging
import sqlite3

from src.core.db import get_connection
from src.model.rating import Rating

logger = logging.getLogger(__name__)


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
        rating = _row_to_rating(row)
        logger.debug(
            "rating guardado",
            extra={
                "layer": "repository",
                "event": "rating_created",
                "rating_id": rating.id,
                "user_id": user_id,
                "item_id": item_id,
                "domain_code": domain_code,
                "status": status,
            },
        )
        return rating
    finally:
        conn.close()


def get_by_user(user_id: int, domain_code: str) -> list[Rating]:
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM ratings WHERE user_id = ? AND domain_code = ?",
            (user_id, domain_code),
        ).fetchall()
        ratings = [_row_to_rating(row) for row in rows]
        logger.debug(
            "ratings cargados",
            extra={
                "layer": "repository",
                "event": "ratings_loaded",
                "user_id": user_id,
                "domain_code": domain_code,
                "count": len(ratings),
            },
        )
        return ratings
    finally:
        conn.close()


def get_by_user_and_item(user_id: int, item_id: int) -> Rating | None:
    conn = get_connection()
    try:
        row = conn.execute(
            "SELECT * FROM ratings WHERE user_id = ? AND item_id = ?", (user_id, item_id)
        ).fetchone()
        rating = _row_to_rating(row) if row is not None else None
        logger.debug(
            "rating buscado por user_id+item_id",
            extra={
                "layer": "repository",
                "event": "rating_lookup_by_user_and_item",
                "user_id": user_id,
                "item_id": item_id,
                "found": rating is not None,
            },
        )
        return rating
    finally:
        conn.close()


def get_by_status(user_id: int, domain_code: str, status: str) -> list[Rating]:
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM ratings WHERE user_id = ? AND domain_code = ? AND status = ?",
            (user_id, domain_code, status),
        ).fetchall()
        ratings = [_row_to_rating(row) for row in rows]
        logger.debug(
            "ratings cargados por status",
            extra={
                "layer": "repository",
                "event": "ratings_loaded_by_status",
                "user_id": user_id,
                "domain_code": domain_code,
                "status": status,
                "count": len(ratings),
            },
        )
        return ratings
    finally:
        conn.close()


def get_by_id(rating_id: int) -> Rating | None:
    conn = get_connection()
    try:
        row = conn.execute("SELECT * FROM ratings WHERE id = ?", (rating_id,)).fetchone()
        rating = _row_to_rating(row) if row is not None else None
        logger.debug(
            "rating buscado por id",
            extra={
                "layer": "repository",
                "event": "rating_lookup",
                "rating_id": rating_id,
                "found": rating is not None,
            },
        )
        return rating
    finally:
        conn.close()


def update_status(rating_id: int, status: str) -> Rating | None:
    conn = get_connection()
    try:
        conn.execute(
            "UPDATE ratings SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (status, rating_id),
        )
        conn.commit()
        row = conn.execute("SELECT * FROM ratings WHERE id = ?", (rating_id,)).fetchone()
        rating = _row_to_rating(row) if row is not None else None
        logger.debug(
            "rating actualizado",
            extra={
                "layer": "repository",
                "event": "rating_status_updated",
                "rating_id": rating_id,
                "status": status,
                "found": rating is not None,
            },
        )
        return rating
    finally:
        conn.close()
