# tests/repositories/test_user_profile_repository.py
from src.repositories import user_profile_repository, user_repository


def test_get_sin_perfil_devuelve_none(temp_db):
    user = user_repository.get_or_create_by_device_id("device-1")

    assert user_profile_repository.get(user.id) is None


def test_upsert_crea_si_no_existe(temp_db):
    user = user_repository.get_or_create_by_device_id("device-1")

    profile = user_profile_repository.upsert(
        user.id, age=28, gender="prefiero no decirlo"
    )

    assert profile.user_id == user.id
    assert profile.age == 28
    assert profile.gender == "prefiero no decirlo"
    assert user_profile_repository.get(user.id) == profile


def test_upsert_actualiza_si_ya_existe(temp_db):
    user = user_repository.get_or_create_by_device_id("device-1")
    user_profile_repository.upsert(user.id, age=28, gender="prefiero no decirlo")

    updated = user_profile_repository.upsert(user.id, age=31, gender="otro")

    assert updated.user_id == user.id
    assert updated.age == 31
    assert updated.gender == "otro"
    assert user_profile_repository.get(user.id).age == 31
