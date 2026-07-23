# src/api/routes/profile_routes.py
import logging

from flask import Blueprint, jsonify, request

from src.api.routes._shared import require_enabled_domain
from src.core.errors import ValidationError
from src.repositories import (
    preference_repository,
    user_profile_repository,
    user_repository,
)

logger = logging.getLogger(__name__)

profile_bp = Blueprint("profile", __name__)

# Rangos de validación (ver ARCHITECTURE.md sección 9: age es filtro duro futuro,
# gender se guarda pero no entra en scoring — ninguno de los dos se valida más allá
# de forma en este bloque).
MIN_AGE = 1
MAX_AGE = 120
MIN_PREFERENCE_WEIGHT = 0.0
MAX_PREFERENCE_WEIGHT = 1.0


def _validate_age(age: object) -> int | None:
    if age is None:
        return None
    if (
        isinstance(age, bool)
        or not isinstance(age, int)
        or not (MIN_AGE <= age <= MAX_AGE)
    ):
        raise ValidationError(f"age debe ser un entero entre {MIN_AGE} y {MAX_AGE}")
    return age


def _validate_preferences(raw_preferences: object) -> list[tuple[str, float]]:
    if not isinstance(raw_preferences, list):
        raise ValidationError("preferences debe ser una lista de objetos {tag, weight}")

    preferences: list[tuple[str, float]] = []
    for entry in raw_preferences:
        if not isinstance(entry, dict):
            raise ValidationError("cada preferencia debe ser un objeto {tag, weight}")

        tag = entry.get("tag")
        weight = entry.get("weight")

        if not tag or not isinstance(tag, str):
            raise ValidationError("tag es obligatorio y debe ser texto")
        if (
            isinstance(weight, bool)
            or not isinstance(weight, (int, float))
            or not (MIN_PREFERENCE_WEIGHT <= weight <= MAX_PREFERENCE_WEIGHT)
        ):
            raise ValidationError(
                f"weight debe ser numérico entre {MIN_PREFERENCE_WEIGHT} y {MAX_PREFERENCE_WEIGHT}"
            )

        preferences.append((tag, float(weight)))

    return preferences


def _require_device_id(source: dict) -> str:
    device_id = source.get("device_id")
    if not device_id:
        raise ValidationError("device_id es obligatorio")
    return device_id


@profile_bp.route("/users/profile", methods=["GET"])
def get_profile():
    device_id = _require_device_id(request.args)

    user = user_repository.get_or_create_by_device_id(device_id)
    profile = user_profile_repository.get(user.id)

    # Un perfil vacío es un estado válido, no un error: 200 con age/gender en null.
    if profile is None:
        return jsonify({"age": None, "gender": None}), 200

    return jsonify({"age": profile.age, "gender": profile.gender}), 200


@profile_bp.route("/users/profile", methods=["PUT"])
def update_profile():
    body = request.get_json(silent=True) or {}
    device_id = _require_device_id(body)

    age = _validate_age(body.get("age"))
    gender = body.get("gender")

    user = user_repository.get_or_create_by_device_id(device_id)
    profile = user_profile_repository.upsert(user.id, age=age, gender=gender)

    logger.info(
        "perfil de usuario actualizado",
        extra={"layer": "api", "event": "user_profile_updated", "user_id": user.id},
    )

    return jsonify({"age": profile.age, "gender": profile.gender}), 200


@profile_bp.route("/users/domains/<domain_code>/preferences", methods=["GET"])
def get_preferences(domain_code: str):
    require_enabled_domain(domain_code)

    device_id = _require_device_id(request.args)

    user = user_repository.get_or_create_by_device_id(device_id)
    preferences = preference_repository.get_by_domain(user.id, domain_code)

    return jsonify([{"tag": tag, "weight": weight} for tag, weight in preferences]), 200


@profile_bp.route("/users/domains/<domain_code>/preferences", methods=["PUT"])
def update_preferences(domain_code: str):
    require_enabled_domain(domain_code)

    body = request.get_json(silent=True) or {}
    device_id = _require_device_id(body)

    preferences = _validate_preferences(body.get("preferences"))

    user = user_repository.get_or_create_by_device_id(device_id)
    preference_repository.set_preferences(user.id, domain_code, preferences)

    logger.info(
        "preferencias explícitas actualizadas",
        extra={
            "layer": "api",
            "event": "preferences_updated",
            "user_id": user.id,
            "domain_code": domain_code,
            "count": len(preferences),
        },
    )

    return jsonify([{"tag": tag, "weight": weight} for tag, weight in preferences]), 200
