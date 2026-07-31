# src/services/recommendation_service.py
import logging
from collections import Counter

from src.core.errors import ValidationError
from src.model.tfidf_engine import TFIDFRecommendationEngine
from src.repositories import (
    blacklist_repository,
    item_repository,
    preference_repository,
    rating_repository,
    signal_weight_repository,
)

logger = logging.getLogger(__name__)

# Todos los status posibles de un rating (ver docs/ARCHITECTURE.md sección 9,
# signal_weights) — se reportan siempre en el desglose de logging.
KNOWN_SIGNAL_STATUSES = ("interested", "rejected")


def generate_recommendations(
    user_id: int, domain_code: str, top_n: int = 10
) -> list[dict]:
    logger.info(
        "generando recomendaciones",
        extra={
            "layer": "service",
            "event": "generate_recommendations_started",
            "user_id": user_id,
            "domain_code": domain_code,
        },
    )

    ratings = rating_repository.get_by_user(user_id, domain_code)
    if not ratings:
        raise ValidationError("El usuario no tiene ratings en este dominio todavía")

    # Base del shrinkage (ver docs/ARCHITECTURE.md sección 9): el total de ratings
    # con señal real (interested/rejected) del usuario en este dominio. Los
    # "skipped" no entrenan el perfil (sección 7.1) y no deben inflar este conteo,
    # aunque sí sean filas en `ratings`.
    total_ratings = sum(
        1 for rating in ratings if rating.status in KNOWN_SIGNAL_STATUSES
    )

    signal_weights = signal_weight_repository.get_all()

    rated_item_ids: list[int] = []
    weight_by_item_id: dict[int, float] = {}
    status_counts: Counter[str] = Counter()

    for rating in ratings:
        weight = signal_weights.get(rating.status)
        if weight is None:
            logger.warning(
                "status de rating sin peso configurado en signal_weights, se ignora esa señal",
                extra={
                    "layer": "service",
                    "event": "unknown_signal_status",
                    "rating_id": rating.id,
                    "status": rating.status,
                },
            )
            continue
        rated_item_ids.append(rating.item_id)
        weight_by_item_id[rating.item_id] = weight
        status_counts[rating.status] += 1

    items_by_id = {item.id: item for item in item_repository.get_by_ids(rated_item_ids)}
    rated_items = [
        (items_by_id[item_id], weight_by_item_id[item_id])
        for item_id in rated_item_ids
        if item_id in items_by_id
    ]

    if not rated_items:
        raise ValidationError("El usuario no tiene ratings en este dominio todavía")

    explicit_preferences = preference_repository.get_by_domain(user_id, domain_code)
    catalog = item_repository.get_all(domain_code)

    # Blacklist dura (docs/ARCHITECTURE.md sección 3.3): exclusión permanente y
    # explícita de candidatos, distinta de la señal de rechazo (ratings.status=
    # 'rejected') — se filtra del catálogo antes de puntuar, mismo patrón que ya usa
    # seed_routes.py para excluir los ya valorados.
    blacklisted_ids = blacklist_repository.get_item_ids(user_id, domain_code)
    # Blacklist por saga: solo afecta a items con collection_name asignado (hoy solo
    # "movies", ver docs/ARCHITECTURE.md sección 3.3).
    blacklisted_collection_names = (
        blacklist_repository.get_blacklisted_collection_names(user_id, domain_code)
    )
    if blacklisted_ids or blacklisted_collection_names:
        catalog = [
            item
            for item in catalog
            if item.id not in blacklisted_ids
            and item.collection_name not in blacklisted_collection_names
        ]

    engine = TFIDFRecommendationEngine()
    recommendations = engine.recommend(
        rated_items,
        catalog,
        top_n,
        explicit_preferences=explicit_preferences,
        total_ratings=total_ratings,
    )

    logger.info(
        "recomendaciones generadas",
        extra={
            "layer": "service",
            "event": "generate_recommendations_done",
            "user_id": user_id,
            "domain_code": domain_code,
            "rated_count": len(rated_items),
            "catalog_size": len(catalog),
            "result_count": len(recommendations),
            "signal_breakdown": {
                status: status_counts.get(status, 0) for status in KNOWN_SIGNAL_STATUSES
            },
            "explicit_preferences_count": len(explicit_preferences),
            "total_ratings": total_ratings,
        },
    )

    return [
        {
            "item_id": item.id,
            "title": item.title,
            "image_url": item.image_url,
            "external_url": item.external_url,
            "score": score,
        }
        for item, score in recommendations
    ]
