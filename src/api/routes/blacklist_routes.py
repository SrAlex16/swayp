# src/api/routes/blacklist_routes.py
"""Blacklist dura (ver docs/ARCHITECTURE.md sección 3.3): exclusión permanente y
explícita de un ítem, distinta de ratings.status='rejected' — no es señal de
entrenamiento, es "no me lo vuelvas a enseñar nunca"."""

import logging

from flask import Blueprint, jsonify, request

from src.api.routes._shared import require_enabled_domain
from src.core.errors import NotFoundError, ValidationError
from src.repositories import blacklist_repository, item_repository, user_repository

logger = logging.getLogger(__name__)

blacklist_bp = Blueprint("blacklist", __name__)


@blacklist_bp.route("/domains/<domain_code>/blacklist", methods=["POST"])
def add_to_blacklist(domain_code: str):
    require_enabled_domain(domain_code)

    body = request.get_json(silent=True) or {}

    device_id = body.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")

    item_id = body.get("item_id")
    if item_id is None:
        raise ValidationError("item_id es obligatorio")

    item = item_repository.get_by_id(item_id)
    if item is None or item.domain != domain_code:
        raise NotFoundError("El item indicado no existe en este dominio")

    user = user_repository.get_or_create_by_device_id(device_id)
    blacklist_repository.add(user.id, item.id, domain_code)

    # Blacklist por saga (ver docs/ARCHITECTURE.md sección 3.3): solo "movies" tiene
    # collection_name real (TMDB); RAWG no tiene equivalente para videojuegos, así
    # que item.collection_name siempre es None ahí y esta rama nunca se activa.
    collection_blacklisted = None
    if item.collection_name and domain_code == "movies":
        blacklist_repository.add_collection(user.id, domain_code, item.collection_name)
        collection_blacklisted = item.collection_name

    logger.info(
        "item añadido a la blacklist",
        extra={
            "layer": "api",
            "event": "blacklist_item_added",
            "user_id": user.id,
            "item_id": item.id,
            "domain_code": domain_code,
            "collection_blacklisted": collection_blacklisted,
        },
    )

    return jsonify(
        {
            "item_id": item.id,
            "domain_code": domain_code,
            "item_blacklisted": True,
            "collection_blacklisted": collection_blacklisted,
        }
    ), 201
