# tests/repositories/test_preference_repository.py
from src.repositories import preference_repository, user_repository


def test_get_by_domain_vacio_al_principio(temp_db):
    user = user_repository.get_or_create_by_device_id("device-1")

    assert preference_repository.get_by_domain(user.id, "games") == []


def test_set_preferences_guarda_y_get_by_domain_las_devuelve(temp_db):
    user = user_repository.get_or_create_by_device_id("device-1")

    preference_repository.set_preferences(user.id, "games", [("RPG", 1.0), ("Terror", 0.2)])

    preferences = preference_repository.get_by_domain(user.id, "games")
    assert set(preferences) == {("RPG", 1.0), ("Terror", 0.2)}


def test_set_preferences_reemplaza_completamente(temp_db):
    """Mismo comportamiento validado a mano con curl: guardar una lista nueva borra
    la anterior por completo, no la combina."""
    user = user_repository.get_or_create_by_device_id("device-1")
    preference_repository.set_preferences(user.id, "games", [("RPG", 1.0), ("Terror", 0.2)])

    preference_repository.set_preferences(user.id, "games", [("Puzzle", 0.8)])

    preferences = preference_repository.get_by_domain(user.id, "games")
    assert preferences == [("Puzzle", 0.8)]


def test_set_preferences_lista_vacia_borra_todas(temp_db):
    user = user_repository.get_or_create_by_device_id("device-1")
    preference_repository.set_preferences(user.id, "games", [("RPG", 1.0)])

    preference_repository.set_preferences(user.id, "games", [])

    assert preference_repository.get_by_domain(user.id, "games") == []
