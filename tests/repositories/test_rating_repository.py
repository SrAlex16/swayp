# tests/repositories/test_rating_repository.py
import sqlite3
import time

import pytest

from src.repositories import rating_repository, user_repository


@pytest.fixture
def user_and_item(insert_item):
    user = user_repository.get_or_create_by_device_id("device-1")
    item_id = insert_item("games", "g1", "Game One")
    return user, item_id


def test_create_y_get_by_id(user_and_item):
    user, item_id = user_and_item

    created = rating_repository.create(
        user_id=user.id, item_id=item_id, domain_code="games", status="interested", source="onboarding"
    )

    fetched = rating_repository.get_by_id(created.id)

    assert fetched is not None
    assert fetched.id == created.id
    assert fetched.user_id == user.id
    assert fetched.item_id == item_id
    assert fetched.status == "interested"
    assert fetched.source == "onboarding"


def test_get_by_id_inexistente(items_table):
    assert rating_repository.get_by_id(999999) is None


def test_get_by_status(insert_item):
    user = user_repository.get_or_create_by_device_id("device-1")
    item_1 = insert_item("games", "g1", "Game One")
    item_2 = insert_item("games", "g2", "Game Two")
    item_3 = insert_item("games", "g3", "Game Three")

    rating_repository.create(user.id, item_1, "games", status="interested", source="onboarding")
    rating_repository.create(user.id, item_2, "games", status="interested", source="onboarding")
    rating_repository.create(user.id, item_3, "games", status="rejected", source="onboarding")

    interested = rating_repository.get_by_status(user.id, "games", "interested")
    rejected = rating_repository.get_by_status(user.id, "games", "rejected")

    assert {rating.item_id for rating in interested} == {item_1, item_2}
    assert {rating.item_id for rating in rejected} == {item_3}


def test_update_status_actualiza_updated_at(user_and_item):
    user, item_id = user_and_item
    created = rating_repository.create(
        user_id=user.id, item_id=item_id, domain_code="games", status="interested", source="onboarding"
    )

    # CURRENT_TIMESTAMP de SQLite tiene resolución de 1 segundo: hay que esperar
    # de verdad para que updated_at cambie de forma observable como string.
    time.sleep(1.1)

    updated = rating_repository.update_status(created.id, "known_liked")

    assert updated is not None
    assert updated.status == "known_liked"
    assert updated.updated_at != created.updated_at
    assert updated.created_at == created.created_at


def test_update_status_id_inexistente_devuelve_none(items_table):
    assert rating_repository.update_status(999999, "known_liked") is None


def test_get_by_user_and_item_existente(user_and_item):
    user, item_id = user_and_item
    created = rating_repository.create(
        user_id=user.id, item_id=item_id, domain_code="games", status="interested", source="onboarding"
    )

    fetched = rating_repository.get_by_user_and_item(user.id, item_id)

    assert fetched is not None
    assert fetched.id == created.id
    assert fetched.status == "interested"


def test_get_by_user_and_item_inexistente(user_and_item):
    user, item_id = user_and_item

    assert rating_repository.get_by_user_and_item(user.id, item_id) is None


def test_unique_user_item_falla_en_segundo_create(user_and_item):
    """ratings tiene UNIQUE(user_id, item_id) y create() no maneja el conflicto
    (a diferencia de preference_repository/user_profile_repository, que sí usan
    ON CONFLICT DO UPDATE): un segundo create() para el mismo user_id+item_id debe
    propagar sqlite3.IntegrityError sin capturarlo."""
    user, item_id = user_and_item
    rating_repository.create(user.id, item_id, "games", status="interested", source="onboarding")

    with pytest.raises(sqlite3.IntegrityError):
        rating_repository.create(user.id, item_id, "games", status="rejected", source="onboarding")
