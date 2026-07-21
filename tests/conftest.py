# tests/conftest.py
import dataclasses

import pytest

from src.core import db as db_module
from src.model.item import Item


@pytest.fixture
def temp_db(tmp_path, monkeypatch):
    """Aísla cada test en su propio archivo SQLite temporal (borrado solo por
    pytest entre tests vía tmp_path, sin limpieza manual).

    IMPORTANTE: src/core/db.py hace `from src.core.config import config`, así que
    `config` es un nombre propio del módulo db_module, distinto del que ven otros
    módulos que hacen el mismo import. Monkeypatchear src.core.config.config no
    afectaría a lo que db_module.get_connection() resuelve — hay que monkeypatchear
    el nombre tal como vive en db_module para que todos los repositories (que llaman
    a db_module.get_connection(), la misma función, definida una sola vez aquí)
    apunten a la BD temporal.
    """
    db_path = tmp_path / "test_swayp.db"
    test_config = dataclasses.replace(db_module.config, database_path=str(db_path))
    monkeypatch.setattr(db_module, "config", test_config)

    db_module.init_db()

    # Verificación explícita de que la siembra condicional ("solo si la tabla está
    # vacía") se dispara de verdad en una BD nueva, no solo en la real que ya lleva
    # tiempo poblada y donde nunca se ha visto el camino "tabla vacía" en la práctica.
    conn = db_module.get_connection()
    try:
        (domain_count,) = conn.execute("SELECT COUNT(*) FROM domains").fetchone()
        assert domain_count == len(db_module.DEFAULT_DOMAINS), (
            "init_db() no sembró domains en una BD nueva"
        )

        (weight_count,) = conn.execute("SELECT COUNT(*) FROM signal_weights").fetchone()
        assert weight_count == len(db_module.DEFAULT_SIGNAL_WEIGHTS), (
            "init_db() no sembró signal_weights en una BD nueva"
        )
    finally:
        conn.close()

    yield db_path


@pytest.fixture
def sample_items() -> list[Item]:
    """Catálogo sintético pequeño (10 ítems) para los tests del motor del siguiente
    bloque. TF-IDF/SVD necesitan varios ítems por familia temática para generar señal
    real, así que hay dos familias claramente distintas (4 ítems cada una) más 2
    comodines que no encajan bien en ninguna — útiles para tests que comprueben que
    el motor no mezcla temáticas sin relación.

    El texto de cada ítem sigue el mismo patrón que los adapters reales (RawgAdapter):
    título + bloque de género/tags repetido x3 + sinopsis, para que el corpus se
    comporte de forma representativa en los tests.
    """
    dark_fantasy_items = [
        # Familia "dark fantasy / souls-like": ambientación oscura, RPG de acción,
        # dificultad alta, mundo cruel. Pensados para parecerse entre sí en tags y
        # vocabulario de sinopsis.
        Item(
            external_id="df-1",
            domain="games",
            title="Shadow of the Fallen King",
            description="A grim journey through a cursed kingdom, brutal bosses and no mercy.",
            text_for_vectorization=(
                "Shadow of the Fallen King Action RPG Dark Fantasy Souls-like "
                "Action RPG Dark Fantasy Souls-like Action RPG Dark Fantasy Souls-like "
                "A grim journey through a cursed kingdom, brutal bosses and no mercy."
            ),
            tags=["Action", "RPG", "Dark Fantasy", "Souls-like"],
            community_score=0.85,
        ),
        Item(
            external_id="df-2",
            domain="games",
            title="Crimson Requiem",
            description="A knight cursed by blood magic seeks redemption in a decaying empire.",
            text_for_vectorization=(
                "Crimson Requiem Action RPG Dark Fantasy Souls-like "
                "Action RPG Dark Fantasy Souls-like Action RPG Dark Fantasy Souls-like "
                "A knight cursed by blood magic seeks redemption in a decaying empire."
            ),
            tags=["Action", "RPG", "Dark Fantasy", "Souls-like"],
            community_score=0.78,
        ),
        Item(
            external_id="df-3",
            domain="games",
            title="Wraith's Descent",
            description="Descend into a gothic castle full of undead horrors and ancient curses.",
            text_for_vectorization=(
                "Wraith's Descent Action RPG Dark Fantasy Gothic Horror "
                "Action RPG Dark Fantasy Gothic Horror Action RPG Dark Fantasy Gothic Horror "
                "Descend into a gothic castle full of undead horrors and ancient curses."
            ),
            tags=["Action", "RPG", "Dark Fantasy", "Gothic", "Horror"],
            community_score=0.81,
        ),
        Item(
            external_id="df-4",
            domain="games",
            title="Bloodmoon Chronicles",
            description="An open world plagued by a blood moon curse, brutal combat and dark lore.",
            text_for_vectorization=(
                "Bloodmoon Chronicles Action RPG Dark Fantasy Open World "
                "Action RPG Dark Fantasy Open World Action RPG Dark Fantasy Open World "
                "An open world plagued by a blood moon curse, brutal combat and dark lore."
            ),
            tags=["Action", "RPG", "Dark Fantasy", "Open World"],
            community_score=0.9,
        ),
    ]

    puzzle_indie_items = [
        # Familia "puzzle/indie": tono relajado, colorido, mecánicas de puzzle o
        # lógica, nada de combate. Pensados para no compartir vocabulario con la
        # familia de dark fantasy de arriba.
        Item(
            external_id="pz-1",
            domain="games",
            title="Pixel Puzzler",
            description="A colorful relaxing puzzle game about matching shapes and colors.",
            text_for_vectorization=(
                "Pixel Puzzler Puzzle Indie Casual Relaxing "
                "Puzzle Indie Casual Relaxing Puzzle Indie Casual Relaxing "
                "A colorful relaxing puzzle game about matching shapes and colors."
            ),
            tags=["Puzzle", "Indie", "Casual", "Relaxing"],
            community_score=0.7,
        ),
        Item(
            external_id="pz-2",
            domain="games",
            title="Block Harmony",
            description="A minimalist puzzle game about arranging blocks into calm harmony.",
            text_for_vectorization=(
                "Block Harmony Puzzle Indie Casual Minimalist "
                "Puzzle Indie Casual Minimalist Puzzle Indie Casual Minimalist "
                "A minimalist puzzle game about arranging blocks into calm harmony."
            ),
            tags=["Puzzle", "Indie", "Casual", "Minimalist"],
            community_score=0.65,
        ),
        Item(
            external_id="pz-3",
            domain="games",
            title="Garden of Loops",
            description="A cozy puzzle-farming hybrid about growing a peaceful looping garden.",
            text_for_vectorization=(
                "Garden of Loops Puzzle Indie Farming Relaxing "
                "Puzzle Indie Farming Relaxing Puzzle Indie Farming Relaxing "
                "A cozy puzzle-farming hybrid about growing a peaceful looping garden."
            ),
            tags=["Puzzle", "Indie", "Farming", "Relaxing"],
            community_score=0.72,
        ),
        Item(
            external_id="pz-4",
            domain="games",
            title="Tiny Circuit",
            description="A logic puzzle game about wiring tiny circuits to solve clever puzzles.",
            text_for_vectorization=(
                "Tiny Circuit Puzzle Indie Logic Casual "
                "Puzzle Indie Logic Casual Puzzle Indie Logic Casual "
                "A logic puzzle game about wiring tiny circuits to solve clever puzzles."
            ),
            tags=["Puzzle", "Indie", "Logic", "Casual"],
            community_score=0.68,
        ),
    ]

    wildcard_items = [
        # Comodines: no pertenecen a ninguna de las dos familias de arriba, útiles
        # para confirmar que el motor no los recomienda por error cuando el perfil
        # apunta claramente a una de las dos familias.
        Item(
            external_id="wc-1",
            domain="games",
            title="Rapid Strike Squad",
            description="A fast-paced multiplayer shooter with competitive team-based combat.",
            text_for_vectorization=(
                "Rapid Strike Squad Shooter Action Multiplayer Competitive "
                "Shooter Action Multiplayer Competitive Shooter Action Multiplayer Competitive "
                "A fast-paced multiplayer shooter with competitive team-based combat."
            ),
            tags=["Shooter", "Action", "Multiplayer", "Competitive"],
            community_score=0.75,
        ),
        Item(
            external_id="wc-2",
            domain="games",
            title="Letters We Never Sent",
            description="A quiet narrative adventure about family, memory and letters left unsent.",
            text_for_vectorization=(
                "Letters We Never Sent Narrative Adventure Drama Story Rich "
                "Narrative Adventure Drama Story Rich Narrative Adventure Drama Story Rich "
                "A quiet narrative adventure about family, memory and letters left unsent."
            ),
            tags=["Narrative", "Adventure", "Drama", "Story Rich"],
            community_score=0.8,
        ),
    ]

    return dark_fantasy_items + puzzle_indie_items + wildcard_items
