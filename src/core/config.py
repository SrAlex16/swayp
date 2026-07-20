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
# Ancla el default a la raíz del repo, no al cwd del proceso que importe este módulo
# (recommend.py, scripts/populate_catalog.py o, más adelante, la API pueden lanzarse
# desde sitios distintos).
DEFAULT_DATABASE_PATH = str(ROOT_DIR / "data" / "swayp.db")


@dataclass(frozen=True)
class Config:
    rawg_api_key: str | None
    tmdb_api_read_access_token: str | None
    database_path: str
    log_level: str


def load_config() -> Config:
    return Config(
        rawg_api_key=os.environ.get("RAWG_API_KEY"),
        tmdb_api_read_access_token=os.environ.get("TMDB_API_READ_ACCESS_TOKEN"),
        database_path=os.environ.get("DATABASE_PATH", DEFAULT_DATABASE_PATH),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
    )


config = load_config()
