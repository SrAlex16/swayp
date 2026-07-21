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

CREATE TABLE IF NOT EXISTS signal_weights (
    status TEXT PRIMARY KEY,
    weight REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS user_profile (
    user_id INTEGER PRIMARY KEY REFERENCES users(id),
    age INTEGER,
    gender TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_explicit_preferences (
    user_id INTEGER NOT NULL REFERENCES users(id),
    domain_code TEXT NOT NULL,
    tag TEXT NOT NULL,
    weight REAL NOT NULL DEFAULT 1.0,
    PRIMARY KEY (user_id, domain_code, tag)
);

CREATE TABLE IF NOT EXISTS domains (
    code TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    enabled BOOLEAN DEFAULT 1
);
"""

# Pesos por defecto del modelo de señales (ver docs/ARCHITECTURE.md, sección 9). Solo
# se siembran si la tabla está vacía, para no pisar un ajuste manual posterior.
DEFAULT_SIGNAL_WEIGHTS = {
    "rejected": -1.0,
    "interested": 0.3,
    "known_liked": 1.0,
    "known_disliked": -1.0,
}

# Qué dominios existen como concepto de producto (capa BD) — separado de qué adapter
# de Python implementa cada uno (detalle de código, ver src/adapters/registry.py).
# Solo se siembra si la tabla está vacía.
DEFAULT_DOMAINS = [
    ("games", "Videojuegos", 1),
    ("movies", "Películas", 1),
]


def get_connection(database_path: str | None = None) -> sqlite3.Connection:
    path = Path(database_path or config.database_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(conn: sqlite3.Connection | None = None) -> None:
    """Crea (si no existen) users/ratings/jobs/signal_weights/user_profile/
    user_explicit_preferences/domains. Idempotente; no toca `items`. Siembra los
    valores por defecto de signal_weights y domains solo si esas tablas están
    vacías."""
    owns_connection = conn is None
    conn = conn or get_connection()
    try:
        conn.executescript(SCHEMA)
        conn.commit()

        (count,) = conn.execute("SELECT COUNT(*) FROM signal_weights").fetchone()
        if count == 0:
            conn.executemany(
                "INSERT INTO signal_weights (status, weight) VALUES (?, ?)",
                list(DEFAULT_SIGNAL_WEIGHTS.items()),
            )
            conn.commit()

        (domain_count,) = conn.execute("SELECT COUNT(*) FROM domains").fetchone()
        if domain_count == 0:
            conn.executemany(
                "INSERT INTO domains (code, display_name, enabled) VALUES (?, ?, ?)",
                DEFAULT_DOMAINS,
            )
            conn.commit()
    finally:
        if owns_connection:
            conn.close()
