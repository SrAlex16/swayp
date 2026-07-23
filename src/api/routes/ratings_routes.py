# src/api/routes/ratings_routes.py
import logging

from flask import Blueprint, jsonify, request

from src.api.routes._shared import require_enabled_domain
from src.core.errors import ConflictError, NotFoundError, ValidationError
from src.model.item import Item
from src.model.rating import Rating
from src.repositories import item_repository, rating_repository, user_repository

logger = logging.getLogger(__name__)

ratings_bp = Blueprint("ratings", __name__)

# Modelo de señales completo (ver docs/ARCHITECTURE.md sección 9 y el Bloque 1 del
# motor): interested/rejected llegan del swipe; known_liked/known_disliked se
# alcanzan al confirmar desde la pantalla de Guardados (sección 7.3), normalmente vía
# el PATCH de más abajo, aunque también se aceptan directamente en el POST.
VALID_STATUSES = {"interested", "rejected", "known_liked", "known_disliked"}

# Status que representa "aceptado sin confirmar todavía" — la bandeja de Guardados
# (sección 7.3) vive de este estado hasta que el usuario confirma si ya lo conocía.
PENDING_CONFIRMATION_STATUS = "interested"

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
        item = next(
            (candidate for candidate in catalog if needle in candidate.title.lower()),
            None,
        )
    else:
        raise ValidationError("Debes indicar item_id o item_title")

    if item is None or item.domain != domain_code:
        raise NotFoundError("El item indicado no existe en este dominio")

    return item


def _validate_status(body: dict) -> str:
    status = body.get("status")
    if status not in VALID_STATUSES:
        raise ValidationError(
            f"status debe ser uno de: {', '.join(sorted(VALID_STATUSES))}"
        )
    return status


@ratings_bp.route("/domains/<domain_code>/ratings", methods=["POST"])
def create_rating(domain_code: str):
    require_enabled_domain(domain_code)

    body = request.get_json(silent=True) or {}

    device_id = body.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")

    status = _validate_status(body)
    item = _resolve_item(domain_code, body)
    user = user_repository.get_or_create_by_device_id(device_id)

    # ratings tiene UNIQUE(user_id, item_id): la cola optimista de swipe (ver
    # ARCHITECTURE.md sección 7.1) puede reintentar el mismo POST tras un fallo de
    # red, así que un segundo POST para el mismo usuario+ítem no es necesariamente
    # un error — depende de si el status coincide con el ya guardado.
    existing = rating_repository.get_by_user_and_item(user.id, item.id)
    if existing is not None:
        if existing.status == status:
            logger.info(
                "rating repetido (reintento idempotente)",
                extra={
                    "layer": "api",
                    "event": "rating_create_retry",
                    "rating_id": existing.id,
                    "user_id": user.id,
                    "item_id": item.id,
                    "domain_code": domain_code,
                    "status": status,
                },
            )
            return jsonify(_rating_to_dict(existing)), 200

        raise ConflictError(
            f"Ya existe un rating (id={existing.id}) para este usuario y este item con "
            f"status='{existing.status}'. Usa PATCH /domains/{domain_code}/ratings/{existing.id} "
            "para cambiarlo."
        )

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


@ratings_bp.route("/domains/<domain_code>/ratings/<int:rating_id>", methods=["PATCH"])
def update_rating(domain_code: str, rating_id: int):
    require_enabled_domain(domain_code)

    body = request.get_json(silent=True) or {}

    device_id = body.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")

    status = _validate_status(body)
    user = user_repository.get_or_create_by_device_id(device_id)

    rating = rating_repository.get_by_id(rating_id)
    # Mismo NotFoundError tanto si no existe como si es de otro usuario/dominio: no
    # se revela la existencia de un rating ajeno.
    if rating is None or rating.domain_code != domain_code or rating.user_id != user.id:
        raise NotFoundError(f"Rating {rating_id} no encontrado")

    updated = rating_repository.update_status(rating_id, status)

    logger.info(
        "rating actualizado",
        extra={
            "layer": "api",
            "event": "rating_status_updated",
            "rating_id": rating_id,
            "user_id": user.id,
            "domain_code": domain_code,
            "previous_status": rating.status,
            "status": status,
        },
    )

    return jsonify(_rating_to_dict(updated)), 200


@ratings_bp.route("/domains/<domain_code>/pending-confirmation", methods=["GET"])
def get_pending_confirmation(domain_code: str):
    require_enabled_domain(domain_code)

    device_id = request.args.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")

    user = user_repository.get_or_create_by_device_id(device_id)
    ratings = rating_repository.get_by_status(
        user.id, domain_code, PENDING_CONFIRMATION_STATUS
    )

    pending = []
    for rating in ratings:
        item = item_repository.get_by_id(rating.item_id)
        if item is None:
            # Rating huérfano (el item ya no está en el catálogo); se omite en vez de
            # romper la respuesta.
            continue
        pending.append(
            {
                "rating_id": rating.id,
                "item_id": item.id,
                "title": item.title,
                "image_url": item.image_url,
                "external_url": item.external_url,
                "status": rating.status,
                "created_at": rating.created_at,
            }
        )

    logger.info(
        "pendientes de confirmación servidos",
        extra={
            "layer": "api",
            "event": "pending_confirmation_served",
            "user_id": user.id,
            "domain_code": domain_code,
            "count": len(pending),
        },
    )

    return jsonify(pending), 200
