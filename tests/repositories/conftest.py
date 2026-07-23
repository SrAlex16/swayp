# tests/repositories/conftest.py
"""Fixtures compartidas para los tests de repositories.

`items` no la crea init_db() — ver el docstring de src/core/db.py: "items ya existe
desde la Fase 0 ... y no se toca aquí en absoluto"; en producción la crea
scripts/populate_catalog.py. Aquí se replica su esquema exacto (mismo SQL que ese
script) para poder testear item_repository/rating_repository de forma aislada con
temp_db, sin tocar src/core/db.py ni scripts/populate_catalog.py."""
import json

import pytest

from src.core import db as db_module

ITEMS_SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    external_id TEXT NOT NULL,
    domain TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    text_for_vectorization TEXT,
    tags TEXT,
    community_score REAL,
    image_url TEXT,
    external_url TEXT,
    adapter_version TEXT NOT NULL,
    enrichment_version TEXT NOT NULL,
    fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(domain, external_id)
);
"""


@pytest.fixture
def items_table(temp_db):
    conn = db_module.get_connection()
    try:
        conn.execute(ITEMS_SCHEMA)
        conn.commit()
    finally:
        conn.close()
    return temp_db


@pytest.fixture
def insert_item(items_table):
    """Inserta una fila en `items` directamente (item_repository no expone ningún
    create/insert, solo lectura) y devuelve el id generado."""

    def _insert(domain: str, external_id: str, title: str, **overrides) -> int:
        defaults = {
            "description": "",
            "text_for_vectorization": "",
            "tags": json.dumps([]),
            "community_score": 0.5,
            "image_url": None,
            "external_url": None,
            "adapter_version": "test-0.1",
            "enrichment_version": "test-0.1",
        }
        defaults.update(overrides)

        conn = db_module.get_connection()
        try:
            cursor = conn.execute(
                """
                INSERT INTO items (
                    external_id, domain, title, description, text_for_vectorization,
                    tags, community_score, image_url, external_url,
                    adapter_version, enrichment_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    external_id,
                    domain,
                    title,
                    defaults["description"],
                    defaults["text_for_vectorization"],
                    defaults["tags"],
                    defaults["community_score"],
                    defaults["image_url"],
                    defaults["external_url"],
                    defaults["adapter_version"],
                    defaults["enrichment_version"],
                ),
            )
            conn.commit()
            return cursor.lastrowid
        finally:
            conn.close()

    return _insert
