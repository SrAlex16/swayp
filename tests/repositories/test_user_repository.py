# tests/repositories/test_user_repository.py
from src.core import db as db_module
from src.repositories import user_repository


def test_get_or_create_by_device_id_crea_si_no_existe(temp_db):
    user = user_repository.get_or_create_by_device_id("device-1")

    assert user.id is not None
    assert user.device_id == "device-1"


def test_get_or_create_by_device_id_devuelve_el_mismo_si_ya_existe(temp_db):
    first = user_repository.get_or_create_by_device_id("device-1")
    second = user_repository.get_or_create_by_device_id("device-1")

    assert second.id == first.id
    assert second.device_id == first.device_id

    conn = db_module.get_connection()
    try:
        (count,) = conn.execute(
            "SELECT COUNT(*) FROM users WHERE device_id = ?", ("device-1",)
        ).fetchone()
    finally:
        conn.close()
    assert count == 1
