# src/model/engine.py
from abc import ABC, abstractmethod

from src.model.item import Item


class RecommendationEngine(ABC):
    """Interfaz agnóstica de dominio para motores de recomendación (ver docs/ARCHITECTURE.md, sección 3.1)."""

    @abstractmethod
    def recommend(
        self, liked_items: list[Item], catalog: list[Item], top_n: int
    ) -> list[tuple[Item, float]]:
        """Devuelve hasta top_n pares (Item, score) del catalog, excluyendo liked_items."""
        raise NotImplementedError
