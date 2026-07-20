# src/repositories/item_repository.py
"""Lectura de la tabla `items` (poblada por scripts/populate_catalog.py). Extraído de
recommend.py para que la lógica de mapeo fila->Item viva en un solo sitio."""
import json
import logging
import sqlite3

from src.core.db import get_connection
from src.model.item import Item

logger = logging.getLogger(__name__)


def _row_to_item(row: sqlite3.Row) -> Item:
    return Item(
        id=row["id"],
        external_id=row["external_id"],
        domain=row["domain"],
        title=row["title"],
        description=row["description"] or "",
        text_for_vectorization=row["text_for_vectorization"] or "",
        tags=json.loads(row["tags"]) if row["tags"] else [],
        community_score=row["community_score"] or 0.0,
        image_url=row["image_url"],
        external_url=row["external_url"],
        adapter_version=row["adapter_version"],
        enrichment_version=row["enrichment_version"],
    )


def get_all(domain_code: str) -> list[Item]:
    conn = get_connection()
    try:
        rows = conn.execute(
            "SELECT * FROM items WHERE domain = ?", (domain_code,)
        ).fetchall()
        items = [_row_to_item(row) for row in rows]
        logger.debug(
            "catálogo cargado",
            extra={
                "layer": "repository",
                "event": "items_loaded",
                "domain_code": domain_code,
                "count": len(items),
            },
        )
        return items
    finally:
        conn.close()


def get_by_id(item_id: int) -> Item | None:
    conn = get_connection()
    try:
        row = conn.execute("SELECT * FROM items WHERE id = ?", (item_id,)).fetchone()
        item = _row_to_item(row) if row is not None else None
        logger.debug(
            "item buscado por id",
            extra={
                "layer": "repository",
                "event": "item_lookup",
                "item_id": item_id,
                "found": item is not None,
            },
        )
        return item
    finally:
        conn.close()


def get_by_ids(item_ids: list[int]) -> list[Item]:
    if not item_ids:
        return []

    conn = get_connection()
    try:
        placeholders = ",".join("?" for _ in item_ids)
        rows = conn.execute(
            f"SELECT * FROM items WHERE id IN ({placeholders})", item_ids
        ).fetchall()
        items = [_row_to_item(row) for row in rows]
        logger.debug(
            "items buscados por id",
            extra={
                "layer": "repository",
                "event": "items_lookup",
                "requested": len(item_ids),
                "found": len(items),
            },
        )
        return items
    finally:
        conn.close()
