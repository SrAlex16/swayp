# src/model/engine.py
from abc import ABC, abstractmethod

from src.model.item import Item


class RecommendationEngine(ABC):
    """Interfaz agnóstica de dominio para motores de recomendación (ver docs/ARCHITECTURE.md, sección 3.1)."""

    @abstractmethod
    def recommend(
        self, rated_items: list[tuple[Item, float]], catalog: list[Item], top_n: int
    ) -> list[tuple[Item, float]]:
        """Devuelve hasta top_n pares (Item, score) del catalog, excluyendo cualquier
        ítem presente en rated_items.

        rated_items es una lista de pares (Item, peso): el peso es el de la señal que
        originó esa valoración (ver docs/ARCHITECTURE.md sección 9, signal_weights) y
        puede ser negativo. Un peso negativo debe alejar el vector de perfil de ese
        ítem, no limitarse a excluirlo del catálogo de candidatos — un rechazo activo
        empuja la recomendación en la dirección opuesta a ese ítem, no equivale a no
        haber dicho nada sobre él.
        """
        raise NotImplementedError
