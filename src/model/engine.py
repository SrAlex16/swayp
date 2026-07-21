# src/model/engine.py
from abc import ABC, abstractmethod

from src.model.item import Item


class RecommendationEngine(ABC):
    """Interfaz agnóstica de dominio para motores de recomendación (ver docs/ARCHITECTURE.md, sección 3.1)."""

    @abstractmethod
    def recommend(
        self,
        rated_items: list[tuple[Item, float]],
        catalog: list[Item],
        top_n: int,
        explicit_preferences: list[tuple[str, float]] | None = None,
        strong_signal_count: int = 0,
    ) -> list[tuple[Item, float]]:
        """Devuelve hasta top_n pares (Item, score) del catalog, excluyendo cualquier
        ítem presente en rated_items.

        rated_items es una lista de pares (Item, peso): el peso es el de la señal que
        originó esa valoración (ver docs/ARCHITECTURE.md sección 9, signal_weights) y
        puede ser negativo. Un peso negativo debe alejar el vector de perfil de ese
        ítem, no limitarse a excluirlo del catálogo de candidatos — un rechazo activo
        empuja la recomendación en la dirección opuesta a ese ítem, no equivale a no
        haber dicho nada sobre él.

        explicit_preferences son pares (tag, peso) declarados explícitamente por el
        usuario en su perfil (no señales implícitas del swipe) — ver ARCHITECTURE.md
        sección 9. Son opcionales: si no se pasan, el comportamiento debe ser idéntico
        al de un motor sin concepto de preferencias explícitas.

        strong_signal_count es el nº de señales "fuertes" (known_liked/known_disliked)
        que el usuario acumula en este dominio. Junto con explicit_preferences resuelve
        el shrinkage con pocos datos (ver ARCHITECTURE.md sección 9 y la nota empírica
        añadida allí): con pocas señales fuertes, el perfil debe apoyarse más en las
        preferencias declaradas explícitamente y menos en el vector implícito (que con
        pocos ratings puede quedar dominado por una sola señal, ej. un rechazo);
        conforme crecen las señales fuertes, el peso se desplaza hacia el implícito.
        """
        raise NotImplementedError
