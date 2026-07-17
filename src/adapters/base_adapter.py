# src/adapters/base_adapter.py
from abc import ABC, abstractmethod

from src.model.item import Item


class BaseAdapter(ABC):
    """Interfaz común a todos los adapters por dominio (ver docs/ARCHITECTURE.md, sección 3.1)."""

    @abstractmethod
    def fetch_popular(self, count: int) -> list[Item]:
        """Devuelve hasta `count` ítems normalizados, ordenados por popularidad en la fuente."""
        raise NotImplementedError

    @abstractmethod
    def fetch_by_id(self, external_id: str) -> Item | None:
        """Devuelve el ítem normalizado con ese id externo, o None si no existe/falla."""
        raise NotImplementedError
