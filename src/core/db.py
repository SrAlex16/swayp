# src/core/db.py
"""Conexión a SQLite (sqlite3 estándar, sin ORM) — ver docs/ARCHITECTURE.md, sección
3.3. `items` ya existe desde la Fase 0 (creada por scripts/populate_catalog.py) y no se
toca aquí en absoluto: este módulo solo añade las tablas nuevas de la Fase 1."""
import sqlite3
from pathlib import Path

from src.core.config import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    device_id TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ratings (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    item_id INTEGER NOT NULL REFERENCES items(id),
    domain_code TEXT NOT NULL,
    status TEXT NOT NULL,
    source TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, item_id)
);

CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    user_id INTEGER REFERENCES users(id),
    domain_code TEXT,
    status TEXT NOT NULL,
    engine_version TEXT,
    result TEXT,
    error_message TEXT,
    request_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""


def get_connection(database_path: str | None = None) -> sqlite3.Connection:
    path = Path(database_path or config.database_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(conn: sqlite3.Connection | None = None) -> None:
    """Crea (si no existen) users/ratings/jobs. Idempotente; no toca `items`."""
    owns_connection = conn is None
    conn = conn or get_connection()
    try:
        conn.executescript(SCHEMA)
        conn.commit()
    finally:
        if owns_connection:
            conn.close()
