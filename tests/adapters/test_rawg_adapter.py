# tests/adapters/test_rawg_adapter.py
"""Contract tests de RawgAdapter (ver docs/decisions/0003-normalizacion-de-tags-
heterogeneos.md): verifican que las decisiones de normalización de RAWG concretas
siguen aplicándose, contra una fixture de respuesta cruda realista — no mockean el
motor ni asumen nada del comportamiento, lo ejercitan de verdad."""
import pytest

from src.adapters.rawg_adapter import RawgAdapter

RAWG_BASE_URL = "https://api.rawg.io/api"


def make_rawg_game_detail(game_id: int, name: str) -> dict:
    """Respuesta cruda realista de GET /games/{id}: género real + ruido de
    TAG_DENYLIST mezclados en `tags`, tal como los devuelve RAWG de verdad."""
    return {
        "id": game_id,
        "slug": name.lower().replace(" ", "-"),
        "name": name,
        "description_raw": (
            "A grim tale of a cursed kingdom where a lone knight must destroy "
            "the shadow that consumes it."
        ),
        "rating": 4.25,  # escala 0-5 de RAWG
        "background_image": f"https://media.rawg.io/media/games/{game_id}/cover.jpg",
        "genres": [
            {"id": 4, "name": "Action", "slug": "action"},
            {"id": 5, "name": "RPG", "slug": "role-playing-games-rpg"},
        ],
        "tags": [
            {"id": 40847, "name": "Dark Fantasy", "slug": "dark-fantasy"},
            {"id": 42, "name": "Singleplayer", "slug": "singleplayer"},
            {"id": 7, "name": "Steam Achievements", "slug": "steam-achievements"},
            {"id": 31, "name": "Co-op", "slug": "co-op"},
            {"id": 40836, "name": "Full controller support", "slug": "full-controller-support"},
        ],
    }


@pytest.fixture
def rawg_game_fixture() -> dict:
    return make_rawg_game_detail(3498, "Shadowreign")


@pytest.fixture
def adapter() -> RawgAdapter:
    return RawgAdapter(api_key="test-api-key", request_delay_seconds=0)


def test_to_item_normaliza_community_score(adapter, rawg_game_fixture):
    """RAWG usa escala 0-5; Item.community_score debe quedar en 0-1."""
    item = adapter._to_item(rawg_game_fixture)

    assert item.community_score == pytest.approx(4.25 / 5.0)


def test_to_item_filtra_tag_denylist_del_texto(adapter, rawg_game_fixture):
    """Los términos de TAG_DENYLIST no deben aparecer en text_for_vectorization,
    pero sí deben seguir presentes en Item.tags (se filtran solo del texto de
    vectorización, nunca del campo original)."""
    item = adapter._to_item(rawg_game_fixture)

    denylisted_tags = ["Steam Achievements", "Co-op", "Full controller support"]

    text_lower = item.text_for_vectorization.lower()
    for tag in denylisted_tags:
        assert tag.lower() not in text_lower, f"{tag!r} no debería estar en text_for_vectorization"
        assert tag in item.tags, f"{tag!r} sí debería seguir en Item.tags"

    # La señal de género real sí debe estar presente en el texto.
    assert "dark fantasy" in text_lower
    assert "action" in text_lower
    assert "rpg" in text_lower


def test_to_item_incluye_adapter_version_y_enrichment_version(adapter, rawg_game_fixture):
    item = adapter._to_item(rawg_game_fixture)

    assert item.adapter_version == "rawg-0.1"
    assert item.enrichment_version == "enrich-0.1"


def test_fetch_popular_usa_requests_mock(adapter, requests_mock):
    """Simula 2 páginas de /games (2 juegos cada una) + sus llamadas de detalle, y
    confirma que fetch_popular hace las llamadas HTTP esperadas y devuelve 4 items
    bien formados."""
    page_1 = {
        "results": [{"id": 1}, {"id": 2}],
        "next": f"{RAWG_BASE_URL}/games?page=2",
    }
    page_2 = {
        "results": [{"id": 3}, {"id": 4}],
        "next": None,
    }
    requests_mock.get(f"{RAWG_BASE_URL}/games", [{"json": page_1}, {"json": page_2}])

    for game_id, name in [(1, "Shadowreign"), (2, "Crimson Requiem"), (3, "Wraith's Descent"), (4, "Bloodmoon")]:
        requests_mock.get(
            f"{RAWG_BASE_URL}/games/{game_id}", json=make_rawg_game_detail(game_id, name)
        )

    items = adapter.fetch_popular(4)

    assert len(items) == 4
    assert [item.title for item in items] == ["Shadowreign", "Crimson Requiem", "Wraith's Descent", "Bloodmoon"]
    assert all(item.adapter_version == "rawg-0.1" for item in items)

    # 2 llamadas al listado (una por página) + 4 llamadas de detalle.
    games_list_calls = [
        req for req in requests_mock.request_history if req.path == "/api/games"
    ]
    detail_calls = [
        req for req in requests_mock.request_history if req.path.startswith("/api/games/")
    ]
    assert len(games_list_calls) == 2
    assert len(detail_calls) == 4


def test_fetch_falla_no_revienta(adapter, requests_mock):
    """Si una página falla (500), fetch_popular no debe lanzar excepción sin
    controlar: debe devolver lo que ya tuviera reunido hasta ese punto (comportamiento
    actual: logger.warning + `listing is None: break`)."""
    page_1 = {
        "results": [{"id": 1}, {"id": 2}],
        "next": f"{RAWG_BASE_URL}/games?page=2",
    }
    requests_mock.get(
        f"{RAWG_BASE_URL}/games",
        [{"json": page_1}, {"status_code": 500}],
    )
    requests_mock.get(f"{RAWG_BASE_URL}/games/1", json=make_rawg_game_detail(1, "Shadowreign"))
    requests_mock.get(f"{RAWG_BASE_URL}/games/2", json=make_rawg_game_detail(2, "Crimson Requiem"))

    items = adapter.fetch_popular(4)

    assert len(items) == 2
    assert [item.title for item in items] == ["Shadowreign", "Crimson Requiem"]
