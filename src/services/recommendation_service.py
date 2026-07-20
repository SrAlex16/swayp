# src/services/recommendation_service.py
import logging

from src.core.errors import ValidationError
from src.model.tfidf_engine import TFIDFRecommendationEngine
from src.repositories import item_repository, rating_repository

logger = logging.getLogger(__name__)

# Señal simple de esta fase: solo "interested" cuenta como gusto para el motor. No
# distingue todavía "ya lo conozco" (known_liked/known_disliked) — ver
# docs/ARCHITECTURE.md, roadmap de fases, Fase 3 (señales completas).
LIKED_STATUS = "interested"


def generate_recommendations(user_id: int, domain_code: str, top_n: int = 10) -> list[dict]:
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
    liked_ratings = [rating for rating in ratings if rating.status == LIKED_STATUS]

    if not liked_ratings:
        raise ValidationError("El usuario no tiene ratings en este dominio todavía")

    liked_items = item_repository.get_by_ids([rating.item_id for rating in liked_ratings])
    catalog = item_repository.get_all(domain_code)

    engine = TFIDFRecommendationEngine()
    recommendations = engine.recommend(liked_items, catalog, top_n)

    logger.info(
        "recomendaciones generadas",
        extra={
            "layer": "service",
            "event": "generate_recommendations_done",
            "user_id": user_id,
            "domain_code": domain_code,
            "liked_count": len(liked_items),
            "catalog_size": len(catalog),
            "result_count": len(recommendations),
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
