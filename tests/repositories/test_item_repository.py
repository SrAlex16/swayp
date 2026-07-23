# tests/repositories/test_item_repository.py
from src.repositories import item_repository


def test_get_all_filtra_por_domain_code(insert_item):
    games_id_1 = insert_item("games", "g1", "Game One")
    games_id_2 = insert_item("games", "g2", "Game Two")
    movies_id_1 = insert_item("movies", "m1", "Movie One")

    games = item_repository.get_all("games")
    movies = item_repository.get_all("movies")

    assert {item.id for item in games} == {games_id_1, games_id_2}
    assert {item.id for item in movies} == {movies_id_1}


def test_get_by_id_existente(insert_item):
    item_id = insert_item("games", "g1", "Game One")

    item = item_repository.get_by_id(item_id)

    assert item is not None
    assert item.id == item_id
    assert item.title == "Game One"
    assert item.domain == "games"


def test_get_by_id_inexistente(items_table):
    assert item_repository.get_by_id(999999) is None


def test_get_by_ids_mezcla_existentes_e_inexistentes(insert_item):
    id_1 = insert_item("games", "g1", "Game One")
    id_2 = insert_item("games", "g2", "Game Two")

    items = item_repository.get_by_ids([id_1, id_2, 999999])

    assert {item.id for item in items} == {id_1, id_2}


def test_get_by_ids_vacio(items_table):
    assert item_repository.get_by_ids([]) == []
