# tests/repositories/test_blacklist_repository.py
from src.repositories import blacklist_repository, user_repository


def test_add_es_idempotente(insert_item):
    user = user_repository.get_or_create_by_device_id("device-1")
    item_id = insert_item("games", "g1", "Game One")

    blacklist_repository.add(user.id, item_id, "games")
    blacklist_repository.add(user.id, item_id, "games")

    assert blacklist_repository.get_item_ids(user.id, "games") == {item_id}


def test_get_item_ids_devuelve_lo_esperado(insert_item):
    user = user_repository.get_or_create_by_device_id("device-1")
    item_1 = insert_item("games", "g1", "Game One")
    item_2 = insert_item("games", "g2", "Game Two")
    insert_item("games", "g3", "Game Three")  # nunca se blacklistea

    blacklist_repository.add(user.id, item_1, "games")
    blacklist_repository.add(user.id, item_2, "games")

    assert blacklist_repository.get_item_ids(user.id, "games") == {item_1, item_2}


def test_get_item_ids_vacio_si_nada_blacklisteado(items_table):
    user = user_repository.get_or_create_by_device_id("device-1")

    assert blacklist_repository.get_item_ids(user.id, "games") == set()


def test_get_item_ids_filtra_por_domain_code(insert_item):
    user = user_repository.get_or_create_by_device_id("device-1")
    item_games = insert_item("games", "g1", "Game One")
    item_movies = insert_item("movies", "m1", "Movie One")

    blacklist_repository.add(user.id, item_games, "games")
    blacklist_repository.add(user.id, item_movies, "movies")

    assert blacklist_repository.get_item_ids(user.id, "games") == {item_games}
    assert blacklist_repository.get_item_ids(user.id, "movies") == {item_movies}
