# tests/integration/test_full_flow.py
"""Tests de integración de la API completa vía el test client de Flask
(docs/ARCHITECTURE.md sección 5.1) — cubren los mismos flujos ya validados a mano con
curl durante la sesión, ahora automatizados."""

import time
import uuid

import pytest

POLL_TIMEOUT_SECONDS = 2.0
POLL_INTERVAL_SECONDS = 0.05


def _poll_job_until_done(client, job_id: str) -> dict:
    deadline = time.monotonic() + POLL_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        response = client.get(f"/api/v1/jobs/{job_id}")
        data = response.get_json()
        if data["status"] in ("done", "error"):
            return data
        time.sleep(POLL_INTERVAL_SECONDS)
    pytest.fail(f"El job {job_id} no terminó en {POLL_TIMEOUT_SECONDS}s")


def test_flujo_completo_seed_rating_job_resultado(client, seeded_catalog):
    device_id = "integration-test-user"

    # 1. GET /domains
    domains_response = client.get("/api/v1/domains")
    assert domains_response.status_code == 200
    codes = {domain["code"] for domain in domains_response.get_json()}
    assert codes == {"games", "movies"}

    # 2. GET seed
    seed_response = client.get(
        f"/api/v1/domains/games/seed?device_id={device_id}&count=5"
    )
    assert seed_response.status_code == 200
    seed_items = seed_response.get_json()
    assert len(seed_items) == 5

    # 3. POST ratings para 3 de los items del seed
    rated_item_ids = [item["item_id"] for item in seed_items[:3]]
    for item_id in rated_item_ids:
        rating_response = client.post(
            "/api/v1/domains/games/ratings",
            json={"device_id": device_id, "item_id": item_id, "status": "interested"},
        )
        assert rating_response.status_code == 201

    # 4. POST recommendations/jobs
    job_response = client.post(
        "/api/v1/domains/games/recommendations/jobs", json={"device_id": device_id}
    )
    assert job_response.status_code == 202
    job_id = job_response.get_json()["job_id"]

    # 5. Polling corto hasta done
    job_data = _poll_job_until_done(client, job_id)

    assert job_data["status"] == "done"
    assert "result" in job_data
    result_item_ids = {item["item_id"] for item in job_data["result"]}
    assert len(result_item_ids) > 0
    assert result_item_ids.isdisjoint(rated_item_ids)


@pytest.mark.parametrize(
    ("method", "path", "json_body"),
    [
        ("get", "/api/v1/domains/dominio-inventado/seed?device_id=test", None),
        (
            "post",
            "/api/v1/domains/dominio-inventado/ratings",
            {"device_id": "test", "item_id": 1, "status": "interested"},
        ),
        (
            "patch",
            "/api/v1/domains/dominio-inventado/ratings/1",
            {"device_id": "test", "status": "interested"},
        ),
        (
            "delete",
            "/api/v1/domains/dominio-inventado/ratings/1?device_id=test",
            None,
        ),
        (
            "post",
            "/api/v1/domains/dominio-inventado/blacklist",
            {"device_id": "test", "item_id": 1},
        ),
        (
            "post",
            "/api/v1/domains/dominio-inventado/recommendations/jobs",
            {"device_id": "test"},
        ),
        (
            "get",
            "/api/v1/domains/dominio-inventado/pending-confirmation?device_id=test",
            None,
        ),
        (
            "get",
            "/api/v1/users/domains/dominio-inventado/preferences?device_id=test",
            None,
        ),
        (
            "put",
            "/api/v1/users/domains/dominio-inventado/preferences",
            {"device_id": "test", "preferences": []},
        ),
    ],
)
def test_dominio_inexistente_da_404_en_todas_las_rutas_con_domain_code(
    client, method, path, json_body
):
    response = getattr(client, method)(path, json=json_body)

    assert response.status_code == 404
    assert response.get_json()["error"]["code"] == "NOT_FOUND"


def test_rating_duplicado_mismo_status_es_idempotente(client, insert_item):
    device_id = "integration-test-user"
    item_id = insert_item("games", "ext-1", "Solo Item")

    first = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "interested"},
    )
    assert first.status_code == 201
    first_rating_id = first.get_json()["id"]

    second = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "interested"},
    )
    assert second.status_code == 200
    assert second.get_json()["id"] == first_rating_id


def test_rating_duplicado_status_distinto_da_409(client, insert_item):
    device_id = "integration-test-user"
    item_id = insert_item("games", "ext-1", "Solo Item")

    client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "interested"},
    )

    conflict = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "rejected"},
    )

    assert conflict.status_code == 409
    assert conflict.get_json()["error"]["code"] == "CONFLICT"


def test_rating_skipped_es_aceptado_y_no_va_a_guardados(client, insert_item):
    device_id = "integration-test-user"
    item_id = insert_item("games", "ext-skip", "Solo Item Skip")

    response = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "skipped"},
    )

    assert response.status_code == 201
    assert response.get_json()["status"] == "skipped"

    pending = client.get(
        f"/api/v1/domains/games/pending-confirmation?device_id={device_id}"
    )
    assert pending.status_code == 200
    assert pending.get_json() == []


def test_rating_skipped_reaparece_en_un_seed_posterior(client, insert_item):
    """Regresión: un item marcado como skipped no debe quedar excluido de /seed para
    siempre (bug real encontrado en revisión — seed_routes.py excluía por cualquier
    rating existente sin mirar el status, ver docs/ARCHITECTURE.md sección 7.1)."""
    device_id = "integration-test-user"
    item_id = insert_item("games", "ext-skip", "Solo Item Skip")

    rating_response = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "skipped"},
    )
    assert rating_response.status_code == 201

    seed_response = client.get(
        f"/api/v1/domains/games/seed?device_id={device_id}&count=10"
    )
    assert seed_response.status_code == 200
    seed_item_ids = {item["item_id"] for item in seed_response.get_json()}
    assert item_id in seed_item_ids


def test_pending_confirmation_flujo(client, insert_item):
    device_id = "integration-test-user"
    item_id = insert_item("games", "ext-1", "Solo Item")

    rating_response = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "interested"},
    )
    rating_id = rating_response.get_json()["id"]

    pending_before = client.get(
        f"/api/v1/domains/games/pending-confirmation?device_id={device_id}"
    )
    assert pending_before.status_code == 200
    assert {entry["rating_id"] for entry in pending_before.get_json()} == {rating_id}

    patch_response = client.patch(
        f"/api/v1/domains/games/ratings/{rating_id}",
        json={"device_id": device_id, "status": "rejected"},
    )
    assert patch_response.status_code == 200
    assert patch_response.get_json()["status"] == "rejected"

    pending_after = client.get(
        f"/api/v1/domains/games/pending-confirmation?device_id={device_id}"
    )
    assert pending_after.status_code == 200
    assert pending_after.get_json() == []


def test_delete_rating_propio_da_204_y_desaparece_de_pending_confirmation(
    client, insert_item
):
    device_id = "integration-test-user"
    item_id = insert_item("games", "ext-1", "Solo Item")

    rating_response = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": device_id, "item_id": item_id, "status": "interested"},
    )
    rating_id = rating_response.get_json()["id"]

    pending_before = client.get(
        f"/api/v1/domains/games/pending-confirmation?device_id={device_id}"
    )
    assert {entry["rating_id"] for entry in pending_before.get_json()} == {rating_id}

    delete_response = client.delete(
        f"/api/v1/domains/games/ratings/{rating_id}?device_id={device_id}"
    )
    assert delete_response.status_code == 204
    assert delete_response.data == b""

    pending_after = client.get(
        f"/api/v1/domains/games/pending-confirmation?device_id={device_id}"
    )
    assert pending_after.get_json() == []


def test_delete_rating_de_otro_device_id_da_404(client, insert_item):
    owner_device_id = "integration-test-user-owner"
    other_device_id = "integration-test-user-other"
    item_id = insert_item("games", "ext-1", "Solo Item")

    rating_response = client.post(
        "/api/v1/domains/games/ratings",
        json={"device_id": owner_device_id, "item_id": item_id, "status": "interested"},
    )
    rating_id = rating_response.get_json()["id"]

    delete_response = client.delete(
        f"/api/v1/domains/games/ratings/{rating_id}?device_id={other_device_id}"
    )
    assert delete_response.status_code == 404
    assert delete_response.get_json()["error"]["code"] == "NOT_FOUND"


def test_reset_ratings_vacia_guardados_y_preserva_preferencias_y_blacklist(
    client, insert_item
):
    device_id = "integration-test-user"
    interested_item_id = insert_item("games", "ext-1", "Interested Item")
    rejected_item_id = insert_item("games", "ext-2", "Rejected Item")
    blacklisted_item_id = insert_item("games", "ext-3", "Blacklisted Item")

    client.post(
        "/api/v1/domains/games/ratings",
        json={
            "device_id": device_id,
            "item_id": interested_item_id,
            "status": "interested",
        },
    )
    client.post(
        "/api/v1/domains/games/ratings",
        json={
            "device_id": device_id,
            "item_id": rejected_item_id,
            "status": "rejected",
        },
    )
    client.post(
        "/api/v1/domains/games/blacklist",
        json={"device_id": device_id, "item_id": blacklisted_item_id},
    )
    client.put(
        "/api/v1/users/domains/games/preferences",
        json={
            "device_id": device_id,
            "preferences": [{"tag": "RPG", "weight": 1.0}],
        },
    )

    reset_response = client.delete(
        f"/api/v1/domains/games/ratings?device_id={device_id}"
    )
    assert reset_response.status_code == 200
    assert reset_response.get_json() == {"deleted_count": 2}

    pending_after = client.get(
        f"/api/v1/domains/games/pending-confirmation?device_id={device_id}"
    )
    assert pending_after.get_json() == []

    preferences_after = client.get(
        f"/api/v1/users/domains/games/preferences?device_id={device_id}"
    )
    assert {
        (entry["tag"], entry["weight"]) for entry in preferences_after.get_json()
    } == {("RPG", 1.0)}

    seed_after = client.get(
        f"/api/v1/domains/games/seed?device_id={device_id}&count=10"
    )
    seed_item_ids_after = {item["item_id"] for item in seed_after.get_json()}
    # El blacklisteado sigue excluido del seed aunque se hayan borrado los ratings.
    assert blacklisted_item_id not in seed_item_ids_after
    # El anteriormente valorado sí puede volver a aparecer: el reset borró la señal.
    assert interested_item_id in seed_item_ids_after
    assert rejected_item_id in seed_item_ids_after


def test_reset_ratings_sin_ratings_devuelve_0(client, insert_item):
    device_id = "integration-test-user"

    reset_response = client.delete(
        f"/api/v1/domains/games/ratings?device_id={device_id}"
    )

    assert reset_response.status_code == 200
    assert reset_response.get_json() == {"deleted_count": 0}


def test_perfil_y_preferencias_flujo(client, items_table):
    device_id = "integration-test-user"

    profile_empty = client.get(f"/api/v1/users/profile?device_id={device_id}")
    assert profile_empty.status_code == 200
    assert profile_empty.get_json() == {"age": None, "gender": None}

    profile_put = client.put(
        "/api/v1/users/profile",
        json={"device_id": device_id, "age": 28, "gender": "prefiero no decirlo"},
    )
    assert profile_put.status_code == 200

    profile_after = client.get(f"/api/v1/users/profile?device_id={device_id}")
    assert profile_after.get_json() == {"age": 28, "gender": "prefiero no decirlo"}

    preferences_empty = client.get(
        f"/api/v1/users/domains/games/preferences?device_id={device_id}"
    )
    assert preferences_empty.status_code == 200
    assert preferences_empty.get_json() == []

    client.put(
        "/api/v1/users/domains/games/preferences",
        json={
            "device_id": device_id,
            "preferences": [
                {"tag": "RPG", "weight": 1.0},
                {"tag": "Terror", "weight": 0.2},
            ],
        },
    )
    preferences_after_first_put = client.get(
        f"/api/v1/users/domains/games/preferences?device_id={device_id}"
    )
    assert {
        (entry["tag"], entry["weight"])
        for entry in preferences_after_first_put.get_json()
    } == {("RPG", 1.0), ("Terror", 0.2)}

    client.put(
        "/api/v1/users/domains/games/preferences",
        json={
            "device_id": device_id,
            "preferences": [{"tag": "Puzzle", "weight": 0.8}],
        },
    )
    preferences_after_second_put = client.get(
        f"/api/v1/users/domains/games/preferences?device_id={device_id}"
    )
    # Reemplazo total, no fusión: RPG/Terror ya no deben aparecer.
    assert preferences_after_second_put.get_json() == [{"tag": "Puzzle", "weight": 0.8}]


def test_job_inexistente_da_404(client, items_table):
    fake_job_id = str(uuid.uuid4())

    response = client.get(f"/api/v1/jobs/{fake_job_id}")

    assert response.status_code == 404
    assert response.get_json()["error"]["code"] == "NOT_FOUND"


def test_todas_las_respuestas_incluyen_x_request_id(client, insert_item):
    device_id = "integration-test-user"
    item_id = insert_item("games", "ext-1", "Solo Item")

    responses = [
        client.get("/api/v1/domains"),
        client.get(f"/api/v1/domains/games/seed?device_id={device_id}"),
        client.post(
            "/api/v1/domains/games/ratings",
            json={"device_id": device_id, "item_id": item_id, "status": "interested"},
        ),
        client.get("/api/v1/domains/dominio-inventado/seed?device_id=test"),
        client.get(f"/api/v1/jobs/{uuid.uuid4()}"),
    ]

    for response in responses:
        request_id = response.headers.get("X-Request-Id")
        assert request_id is not None
        assert request_id != ""


def test_blacklist_excluye_de_seed_y_de_recomendaciones(client, seeded_catalog):
    device_id = "integration-test-user"
    blacklisted_item_id = seeded_catalog[0]

    blacklist_response = client.post(
        "/api/v1/domains/games/blacklist",
        json={"device_id": device_id, "item_id": blacklisted_item_id},
    )
    assert blacklist_response.status_code == 201

    seed_response = client.get(
        f"/api/v1/domains/games/seed?device_id={device_id}&count=10"
    )
    assert seed_response.status_code == 200
    seed_item_ids = {item["item_id"] for item in seed_response.get_json()}
    assert blacklisted_item_id not in seed_item_ids

    # Valora unos cuantos items (ninguno el blacklisteado) para poder generar
    # una recomendación real.
    rated_item_ids = [
        item_id for item_id in seeded_catalog if item_id != blacklisted_item_id
    ][:3]
    for item_id in rated_item_ids:
        rating_response = client.post(
            "/api/v1/domains/games/ratings",
            json={"device_id": device_id, "item_id": item_id, "status": "interested"},
        )
        assert rating_response.status_code == 201

    job_response = client.post(
        "/api/v1/domains/games/recommendations/jobs", json={"device_id": device_id}
    )
    assert job_response.status_code == 202
    job_id = job_response.get_json()["job_id"]

    job_data = _poll_job_until_done(client, job_id)
    assert job_data["status"] == "done"
    result_item_ids = {item["item_id"] for item in job_data["result"]}
    assert blacklisted_item_id not in result_item_ids


def test_blacklist_por_saga_excluye_toda_la_saga_de_seed_y_recomendaciones(
    client, insert_item
):
    device_id = "integration-test-user"

    saga_texts = [
        "epic fantasy war dragons kingdom battle",
        "epic fantasy sequel dragons throne siege",
        "epic fantasy finale dragons empire conquest",
    ]
    saga_item_ids = [
        insert_item(
            "movies",
            f"ext-saga-{i}",
            f"Saga Movie {i}",
            text_for_vectorization=text,
            collection_name="La Gran Saga",
        )
        for i, text in enumerate(saga_texts)
    ]
    # Vocabulario deliberadamente distinto entre sí (evita que TfidfVectorizer, con
    # max_df=0.5, pode todos los términos de un corpus tan pequeño por ser
    # demasiado compartidos).
    unrelated_texts = [
        "wizard castle kingdom stone tower",
        "ocean pirates treasure island voyage",
        "space station robots future colony",
    ]
    unrelated_item_ids = [
        insert_item(
            "movies",
            f"ext-unrelated-{i}",
            f"Unrelated Movie {i}",
            text_for_vectorization=text,
        )
        for i, text in enumerate(unrelated_texts)
    ]

    blacklist_response = client.post(
        "/api/v1/domains/movies/blacklist",
        json={"device_id": device_id, "item_id": saga_item_ids[0]},
    )
    assert blacklist_response.status_code == 201
    assert blacklist_response.get_json() == {
        "item_id": saga_item_ids[0],
        "domain_code": "movies",
        "item_blacklisted": True,
        "collection_blacklisted": "La Gran Saga",
    }

    seed_response = client.get(
        f"/api/v1/domains/movies/seed?device_id={device_id}&count=10"
    )
    seed_item_ids = {item["item_id"] for item in seed_response.get_json()}
    assert seed_item_ids.isdisjoint(saga_item_ids)
    assert set(unrelated_item_ids) <= seed_item_ids

    for item_id in unrelated_item_ids:
        rating_response = client.post(
            "/api/v1/domains/movies/ratings",
            json={"device_id": device_id, "item_id": item_id, "status": "interested"},
        )
        assert rating_response.status_code == 201

    job_response = client.post(
        "/api/v1/domains/movies/recommendations/jobs", json={"device_id": device_id}
    )
    job_id = job_response.get_json()["job_id"]
    job_data = _poll_job_until_done(client, job_id)

    assert job_data["status"] == "done"
    result_item_ids = {item["item_id"] for item in job_data["result"]}
    assert result_item_ids.isdisjoint(saga_item_ids)


def test_blacklist_pelicula_sin_saga_no_excluye_nada_mas(client, insert_item):
    device_id = "integration-test-user"

    solo_item_id = insert_item("movies", "ext-solo", "Solo Movie")
    other_item_id = insert_item("movies", "ext-other", "Other Movie")

    blacklist_response = client.post(
        "/api/v1/domains/movies/blacklist",
        json={"device_id": device_id, "item_id": solo_item_id},
    )
    assert blacklist_response.status_code == 201
    assert blacklist_response.get_json()["collection_blacklisted"] is None

    seed_response = client.get(
        f"/api/v1/domains/movies/seed?device_id={device_id}&count=10"
    )
    seed_item_ids = {item["item_id"] for item in seed_response.get_json()}
    assert solo_item_id not in seed_item_ids
    assert other_item_id in seed_item_ids


def test_blacklist_videojuego_nunca_intenta_tocar_collections(client, insert_item):
    device_id = "integration-test-user"

    game_item_id = insert_item("games", "ext-game", "Solo Game")
    other_game_item_id = insert_item("games", "ext-other-game", "Other Game")

    blacklist_response = client.post(
        "/api/v1/domains/games/blacklist",
        json={"device_id": device_id, "item_id": game_item_id},
    )
    assert blacklist_response.status_code == 201
    assert blacklist_response.get_json() == {
        "item_id": game_item_id,
        "domain_code": "games",
        "item_blacklisted": True,
        "collection_blacklisted": None,
    }

    seed_response = client.get(
        f"/api/v1/domains/games/seed?device_id={device_id}&count=10"
    )
    seed_item_ids = {item["item_id"] for item in seed_response.get_json()}
    assert game_item_id not in seed_item_ids
    assert other_game_item_id in seed_item_ids
