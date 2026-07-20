# src/api/routes/seed_routes.py
import logging
import random

from flask import Blueprint, jsonify, request

from src.core.errors import ValidationError
from src.model.item import Item
from src.repositories import item_repository, rating_repository, user_repository

logger = logging.getLogger(__name__)

seed_bp = Blueprint("seed", __name__)

DEFAULT_SEED_COUNT = 20


def _item_to_dict(item: Item) -> dict:
    return {
        "item_id": item.id,
        "title": item.title,
        "description": item.description,
        "tags": item.tags,
        "community_score": item.community_score,
        "image_url": item.image_url,
        "external_url": item.external_url,
    }


@seed_bp.route("/domains/<domain_code>/seed", methods=["GET"])
def get_seed(domain_code: str):
    device_id = request.args.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")

    count_param = request.args.get("count")
    if count_param is None:
        count = DEFAULT_SEED_COUNT
    else:
        try:
            count = int(count_param)
        except ValueError:
            raise ValidationError("count debe ser un entero positivo") from None

    if count <= 0:
        raise ValidationError("count debe ser un entero positivo")

    user = user_repository.get_or_create_by_device_id(device_id)

    # Muestreo aleatorio simple por ahora: la estratificación por género que describe
    # docs/ARCHITECTURE.md queda pendiente en docs/ROADMAP.md, no se implementa aquí.
    catalog = item_repository.get_all(domain_code)
    already_rated_ids = {
        rating.item_id for rating in rating_repository.get_by_user(user.id, domain_code)
    }
    candidates = [item for item in catalog if item.id not in already_rated_ids]

    sample = random.sample(candidates, k=min(count, len(candidates)))

    logger.info(
        "seed de onboarding servido",
        extra={
            "layer": "api",
            "event": "seed_served",
            "user_id": user.id,
            "domain_code": domain_code,
            "requested": count,
            "returned": len(sample),
            "catalog_size": len(catalog),
        },
    )

    return jsonify([_item_to_dict(item) for item in sample]), 200
