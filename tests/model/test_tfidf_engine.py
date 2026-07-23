# tests/model/test_tfidf_engine.py
"""Tests de TFIDFRecommendationEngine (docs/ARCHITECTURE.md sección 5.1). Cada test
codifica una validación manual real hecha durante el desarrollo — los valores
concretos (scores, órdenes) se obtuvieron ejecutando el motor contra sample_items
antes de escribir las aserciones, no se asumieron."""

import logging

import pytest

from src.model.tfidf_engine import TFIDFRecommendationEngine

DARK_FANTASY_IDS = {"df-1", "df-2", "df-3", "df-4"}
PUZZLE_INDIE_IDS = {"pz-1", "pz-2", "pz-3", "pz-4"}


@pytest.fixture
def items_by_id(sample_items):
    return {item.external_id: item for item in sample_items}


@pytest.fixture
def engine():
    return TFIDFRecommendationEngine()


def test_ignora_items_sin_senal_declarada(engine, sample_items, items_by_id):
    """Solo señales positivas (peso 1.0) de la familia dark-fantasy: el top debe
    estar dominado por el resto de esa familia (df-2, df-3, df-4), por encima de
    toda la familia puzzle/indie."""
    rated_items = [(items_by_id["df-1"], 1.0)]

    recommendations = engine.recommend(rated_items, sample_items, top_n=3)

    top_3_ids = {item.external_id for item, _ in recommendations}
    assert top_3_ids == {"df-2", "df-3", "df-4"}

    min_dark_fantasy_score = min(score for item, score in recommendations)
    puzzle_scores = [
        score
        for item, score in engine.recommend(
            rated_items, sample_items, top_n=len(sample_items)
        )
        if item.external_id in PUZZLE_INDIE_IDS
    ]
    assert all(min_dark_fantasy_score > puzzle_score for puzzle_score in puzzle_scores)


def test_senal_negativa_aleja_items_similares(engine, sample_items, items_by_id):
    """Replica la prueba manual real del Bloque 1 de señales: 2 items dark-fantasy
    con el peso real de 'interested' (0.3) + 1 item muy similar en tags/texto
    (misma familia) con el peso real de 'rejected' (-1.0, más fuerte que los dos
    positivos combinados: 0.3+0.3=0.6 < 1.0). El ítem no valorado más parecido al
    rechazado (df-4, comparte "Action RPG Dark Fantasy" con df-3) debe terminar con
    similarity_score negativo y en la última posición del ranking — no solo fuera
    del top, sino demostrablemente repelido."""
    rated_items = [
        (items_by_id["df-1"], 0.3),
        (items_by_id["df-2"], 0.3),
        (items_by_id["df-3"], -1.0),
    ]

    scored = engine._score_catalog(rated_items, sample_items)
    scored.sort(key=lambda entry: entry.final_score, reverse=True)

    # df-3 (rechazado) no debe aparecer en absoluto: es un rated_item.
    assert "df-3" not in {entry.item.external_id for entry in scored}

    last = scored[-1]
    assert last.item.external_id == "df-4"
    assert last.similarity_score < 0


def test_fallback_peso_cero(engine, sample_items, items_by_id, caplog):
    """rated_items con un único item de peso 0.0: no debe lanzar excepción, debe
    ordenar por community_score (verificado contra los community_score reales de
    sample_items) y debe loguear el warning de fallback."""
    rated_items = [(items_by_id["df-1"], 0.0)]

    with caplog.at_level(logging.WARNING, logger="src.model.tfidf_engine"):
        recommendations = engine.recommend(
            rated_items, sample_items, top_n=len(sample_items)
        )

    expected_order = [
        "df-4",
        "df-3",
        "wc-2",
        "df-2",
        "wc-1",
        "pz-3",
        "pz-1",
        "pz-4",
        "pz-2",
    ]
    assert [item.external_id for item, _ in recommendations] == expected_order

    for item, score in recommendations:
        assert score == pytest.approx(item.community_score)

    warning_records = [
        record for record in caplog.records if record.levelno == logging.WARNING
    ]
    assert len(warning_records) == 1
    assert warning_records[0].event == "zero_weight_profile_fallback"
    assert warning_records[0].rated_count == 1


def test_excluye_todos_los_items_valorados(engine, sample_items, items_by_id):
    """rated_items mixto (positivos y negativos): ninguno debe aparecer en el
    resultado, independientemente de su status/peso."""
    rated_items = [
        (items_by_id["df-1"], 0.3),
        (items_by_id["pz-1"], -1.0),
        (items_by_id["wc-1"], 1.0),
    ]
    rated_ids = {item.external_id for item, _ in rated_items}

    recommendations = engine.recommend(
        rated_items, sample_items, top_n=len(sample_items)
    )

    result_ids = {item.external_id for item, _ in recommendations}
    assert result_ids.isdisjoint(rated_ids)
    assert len(recommendations) == len(sample_items) - len(rated_items)


def test_shrinkage_sin_preferencias_explicitas_no_cambia_nada(
    engine, sample_items, items_by_id
):
    """Sin pasar explicit_preferences, o pasando explicit_preferences=None
    explícitamente (los dos son el default): el resultado debe ser idéntico."""
    rated_items = [(items_by_id["df-1"], 0.3), (items_by_id["df-2"], 0.3)]

    without_kwarg = engine.recommend(rated_items, sample_items, top_n=5)
    with_explicit_none = engine.recommend(
        rated_items, sample_items, top_n=5, explicit_preferences=None
    )

    assert without_kwarg == with_explicit_none


def test_shrinkage_con_cero_senales_fuertes_usa_preferencia_explicita(
    engine, sample_items, items_by_id
):
    """Replica la prueba manual real del Bloque 2 de perfil: rated_items normales
    (dark-fantasy) + explicit_preferences hacia el tag de la familia puzzle/indie +
    strong_signal_count=0 (w_explicit=1.0: el vector de perfil se apoya al 100% en
    lo declarado). El resultado debe favorecer la familia puzzle/indie por encima de
    dark-fantasy, invirtiendo lo que darían las señales implícitas solas."""
    rated_items = [(items_by_id["df-1"], 0.3), (items_by_id["df-2"], 0.3)]

    recommendations = engine.recommend(
        rated_items,
        sample_items,
        top_n=4,
        explicit_preferences=[("Puzzle", 1.0)],
        strong_signal_count=0,
    )

    top_4_ids = {item.external_id for item, _ in recommendations}
    assert top_4_ids == PUZZLE_INDIE_IDS


def test_recommend_respeta_top_n(engine, sample_items, items_by_id):
    """top_n=3 con más de 3 candidatos posibles: deben devolverse exactamente 3."""
    rated_items = [(items_by_id["df-1"], 1.0)]

    recommendations = engine.recommend(rated_items, sample_items, top_n=3)

    assert len(recommendations) == 3


def test_rated_items_vacio_lanza_error(engine, sample_items):
    """rated_items=[] debe lanzar ValueError, tal como hace _score_catalog hoy."""
    with pytest.raises(ValueError, match="rated_items no puede estar vacío"):
        engine.recommend([], sample_items, top_n=5)
