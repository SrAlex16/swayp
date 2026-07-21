# scripts/populate_catalog.py
"""Puebla data/swayp.db con el catálogo de un dominio (Fase 0/1, ver docs/TODO.md).
Por defecto sigue poblando videojuegos vía RawgAdapter, igual que en la Fase 0; usa
--domain movies para poblar películas vía TmdbAdapter."""
import argparse
import json
import logging
import sqlite3
import sys
from pathlib import Path

from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from src.adapters.registry import ADAPTER_REGISTRY  # noqa: E402
from src.model.item import Item  # noqa: E402

DEFAULT_DOMAIN = "games"

DB_PATH = ROOT_DIR / "data" / "swayp.db"

SCHEMA = """
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

UPSERT = """
INSERT INTO items (
    external_id, domain, title, description, text_for_vectorization,
    tags, community_score, image_url, external_url,
    adapter_version, enrichment_version
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(domain, external_id) DO UPDATE SET
    title=excluded.title,
    description=excluded.description,
    text_for_vectorization=excluded.text_for_vectorization,
    tags=excluded.tags,
    community_score=excluded.community_score,
    image_url=excluded.image_url,
    external_url=excluded.external_url,
    adapter_version=excluded.adapter_version,
    enrichment_version=excluded.enrichment_version,
    fetched_at=CURRENT_TIMESTAMP
"""

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def get_connection() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(SCHEMA)
    return conn


def save_item(conn: sqlite3.Connection, item: Item) -> None:
    conn.execute(
        UPSERT,
        (
            item.external_id,
            item.domain,
            item.title,
            item.description,
            item.text_for_vectorization,
            json.dumps(item.tags, ensure_ascii=False),
            item.community_score,
            item.image_url,
            item.external_url,
            item.adapter_version,
            item.enrichment_version,
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Puebla el catálogo de un dominio")
    parser.add_argument(
        "--domain",
        choices=sorted(ADAPTER_REGISTRY),
        default=DEFAULT_DOMAIN,
        help=f"Dominio a poblar (default: {DEFAULT_DOMAIN})",
    )
    parser.add_argument("--count", type=int, default=200, help="Número de ítems a descargar")
    args = parser.parse_args()

    load_dotenv()

    adapter_cls = ADAPTER_REGISTRY[args.domain]
    adapter = adapter_cls()
    logger.info("Descargando %d ítems populares de '%s' (%s)...", args.count, args.domain, adapter_cls.__name__)
    items = adapter.fetch_popular(args.count)

    conn = get_connection()
    with conn:
        for item in items:
            save_item(conn, item)
    conn.close()

    logger.info("Guardados %d/%d ítems de '%s' en %s", len(items), args.count, args.domain, DB_PATH)


if __name__ == "__main__":
    main()
