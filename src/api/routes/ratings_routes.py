# src/api/routes/ratings_routes.py
import logging

from flask import Blueprint, jsonify, request

from src.core.errors import NotFoundError, ValidationError
from src.model.item import Item
from src.model.rating import Rating
from src.repositories import item_repository, rating_repository, user_repository

logger = logging.getLogger(__name__)

ratings_bp = Blueprint("ratings", __name__)

# Señal simple de esta fase: solo interested/rejected. known_liked/known_disliked
# (distinguir "ya lo conozco") llega en la Fase 3 — ver docs/ARCHITECTURE.md roadmap.
VALID_STATUSES = {"interested", "rejected"}

# El origen de este rating siempre es la baraja de onboarding en esta fase: el único
# productor de items es GET /domains/<domain_code>/seed (ver seed_routes.py).
RATING_SOURCE = "onboarding"


def _rating_to_dict(rating: Rating) -> dict:
    return {
        "id": rating.id,
        "user_id": rating.user_id,
        "item_id": rating.item_id,
        "domain_code": rating.domain_code,
        "status": rating.status,
        "source": rating.source,
        "created_at": rating.created_at,
        "updated_at": rating.updated_at,
    }


def _resolve_item(domain_code: str, body: dict) -> Item:
    item_id = body.get("item_id")
    item_title = body.get("item_title")

    if item_id is not None:
        item = item_repository.get_by_id(item_id)
    elif item_title:
        needle = str(item_title).strip().lower()
        catalog = item_repository.get_all(domain_code)
        item = next((candidate for candidate in catalog if needle in candidate.title.lower()), None)
    else:
        raise ValidationError("Debes indicar item_id o item_title")

    if item is None or item.domain != domain_code:
        raise NotFoundError("El item indicado no existe en este dominio")

    return item


@ratings_bp.route("/domains/<domain_code>/ratings", methods=["POST"])
def create_rating(domain_code: str):
    body = request.get_json(silent=True) or {}

    device_id = body.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")

    status = body.get("status")
    if status not in VALID_STATUSES:
        raise ValidationError(f"status debe ser uno de: {', '.join(sorted(VALID_STATUSES))}")

    item = _resolve_item(domain_code, body)
    user = user_repository.get_or_create_by_device_id(device_id)

    rating = rating_repository.create(
        user_id=user.id,
        item_id=item.id,
        domain_code=domain_code,
        status=status,
        source=RATING_SOURCE,
    )

    logger.info(
        "rating creado",
        extra={
            "layer": "api",
            "event": "rating_created",
            "rating_id": rating.id,
            "user_id": user.id,
            "item_id": item.id,
            "domain_code": domain_code,
            "status": status,
        },
    )

    return jsonify(_rating_to_dict(rating)), 201
