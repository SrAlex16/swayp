# tests/adapters/test_tmdb_adapter.py
"""Contract tests de TmdbAdapter (ver docs/decisions/0003-normalizacion-de-tags-
heterogeneos.md): verifican que las decisiones de normalización de TMDB concretas
siguen aplicándose, contra una fixture de respuesta cruda realista."""

import pytest

from src.adapters.tmdb_adapter import TmdbAdapter

TMDB_BASE_URL = "https://api.themoviedb.org/3"


def make_tmdb_movie_detail(
    movie_id: int, title: str, *, with_collection: bool = True
) -> dict:
    """Respuesta cruda realista de GET /movie/{id}?append_to_response=keywords."""
    detail = {
        "id": movie_id,
        "title": title,
        "overview": (
            "A retired soldier must confront his past when a mysterious ember "
            "reignites an ancient war."
        ),
        "tagline": "The past never truly dies.",
        "vote_average": 7.4,  # escala 0-10 de TMDB
        "vote_count": 1200,
        "poster_path": f"/{movie_id}-poster.jpg",
        "adult": False,
        "genres": [
            {"id": 28, "name": "Action"},
            {"id": 12, "name": "Adventure"},
        ],
        "belongs_to_collection": (
            {
                "id": 9999,
                "name": "The Last Ember Collection",
                "poster_path": "/collection-poster.jpg",
                "backdrop_path": "/collection-backdrop.jpg",
            }
            if with_collection
            else None
        ),
        "keywords": {
            "keywords": [
                {"id": 1701, "name": "war"},
                {"id": 2021, "name": "redemption"},
                {"id": 3099, "name": "ancient prophecy"},
            ]
        },
    }
    return detail


@pytest.fixture
def tmdb_movie_fixture() -> dict:
    return make_tmdb_movie_detail(550988, "The Last Ember")


@pytest.fixture
def adapter() -> TmdbAdapter:
    return TmdbAdapter(api_read_access_token="test-token", request_delay_seconds=0)


def test_to_item_normaliza_community_score(adapter, tmdb_movie_fixture):
    """TMDB usa escala 0-10; Item.community_score debe quedar en 0-1."""
    item = adapter._to_item(tmdb_movie_fixture)

    assert item.community_score == pytest.approx(7.4 / 10.0)


def test_to_item_incluye_tagline_y_coleccion_en_texto(adapter, tmdb_movie_fixture):
    item = adapter._to_item(tmdb_movie_fixture)

    assert "The past never truly dies." in item.text_for_vectorization
    assert "The Last Ember Collection" in item.text_for_vectorization


def test_to_item_sin_coleccion_no_rompe(adapter):
    """belongs_to_collection=None no debe lanzar excepción; el texto se construye
    igual, simplemente sin el bloque de colección."""
    fixture_without_collection = make_tmdb_movie_detail(
        550988, "The Last Ember", with_collection=False
    )

    item = adapter._to_item(fixture_without_collection)

    assert "The Last Ember Collection" not in item.text_for_vectorization
    # El resto de la señal estructurada sigue presente.
    assert "The past never truly dies." in item.text_for_vectorization
    assert "war" in item.text_for_vectorization
    assert "Action" in item.text_for_vectorization


def test_fetch_popular_excluye_adult(adapter, requests_mock):
    """Una entrada con adult=true en el listado no debe aparecer en el resultado ni
    debe gastar una llamada de detalle: el detalle de esa película deliberadamente
    NO se registra en requests_mock, así que si el código la llamara igualmente,
    requests_mock lanzaría NoMockAddress y el test fallaría con un error claro."""
    listing = {
        "page": 1,
        "results": [
            {"id": 100, "title": "Safe Movie One", "adult": False},
            {"id": 200, "title": "Adult Movie", "adult": True},
            {"id": 300, "title": "Safe Movie Two", "adult": False},
        ],
        "total_pages": 1,
        "total_results": 3,
    }
    requests_mock.get(f"{TMDB_BASE_URL}/movie/popular", json=listing)
    requests_mock.get(
        f"{TMDB_BASE_URL}/movie/100", json=make_tmdb_movie_detail(100, "Safe Movie One")
    )
    requests_mock.get(
        f"{TMDB_BASE_URL}/movie/300", json=make_tmdb_movie_detail(300, "Safe Movie Two")
    )
    # Sin registrar /movie/200 a propósito.

    items = adapter.fetch_popular(3)

    assert len(items) == 2
    assert {item.external_id for item in items} == {"100", "300"}
