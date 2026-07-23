# tests/integration/conftest.py
"""Fixtures compartidas para los tests de integración de la API (Flask test client
contra temp_db). Mismo patrón que tests/repositories/conftest.py para la tabla
`items` (no la crea init_db(), ver su docstring en src/core/db.py) — se replica aquí
también porque estos tests necesitan items reales de catálogo para ejercitar
seed/ratings/jobs de principio a fin."""

import json

import pytest

from src.api.app import create_app
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
            "text_for_vectorization": title,
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


@pytest.fixture
def client(items_table):
    app = create_app()
    return app.test_client()


@pytest.fixture
def seeded_catalog(insert_item) -> list[int]:
    """10 items reales en el dominio 'games', con texto lo bastante distinto entre
    sí para que TF-IDF/SVD tengan vocabulario real con el que trabajar (no es un
    test del motor, pero el job de recomendaciones sí lo ejecuta de verdad)."""
    titles = [
        "Shadow of the Fallen King",
        "Crimson Requiem",
        "Wraith's Descent",
        "Bloodmoon Chronicles",
        "Pixel Puzzler",
        "Block Harmony",
        "Garden of Loops",
        "Tiny Circuit",
        "Rapid Strike Squad",
        "Letters We Never Sent",
    ]
    return [
        insert_item(
            "games",
            f"ext-{i}",
            title,
            text_for_vectorization=f"{title} adventure story world game",
            community_score=0.5 + (i % 5) / 10,
        )
        for i, title in enumerate(titles)
    ]
