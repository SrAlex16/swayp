# src/core/config.py
"""Configuración centralizada vía variables de entorno (ver docs/ARCHITECTURE.md,
sección 3.7): sustituye los os.environ.get() dispersos por el código (usada por los
adapters de cada dominio, ej. rawg_adapter.py, tmdb_adapter.py)."""

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
# Ancla los defaults a la raíz del repo, no al cwd del proceso que importe este módulo
# (recommend.py, scripts/populate_catalog.py o, más adelante, la API pueden lanzarse
# desde sitios distintos).
DEFAULT_DATABASE_PATH = str(ROOT_DIR / "data" / "swayp.db")
DEFAULT_LOG_DIR = str(ROOT_DIR / "logs")


@dataclass(frozen=True)
class Config:
    rawg_api_key: str | None
    tmdb_api_read_access_token: str | None
    database_path: str
    log_level: str
    log_dir: str
    log_rotation_interval: str  # "hourly" | "daily" | "weekly"
    log_retention_count: int


def load_config() -> Config:
    return Config(
        rawg_api_key=os.environ.get("RAWG_API_KEY"),
        tmdb_api_read_access_token=os.environ.get("TMDB_API_READ_ACCESS_TOKEN"),
        database_path=os.environ.get("DATABASE_PATH", DEFAULT_DATABASE_PATH),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
        log_dir=os.environ.get("LOG_DIR", DEFAULT_LOG_DIR),
        log_rotation_interval=os.environ.get("LOG_ROTATION_INTERVAL", "daily"),
        log_retention_count=int(os.environ.get("LOG_RETENTION_COUNT", "14")),
    )


config = load_config()
