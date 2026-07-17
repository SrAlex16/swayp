# recommend.py
"""CLI de validación manual del motor de recomendación (Fase 0, ver docs/TODO.md).

Uso:
    python recommend.py --user test --likes "Elden Ring" "Dark Souls" "Hollow Knight"
"""
import argparse
import json
import sqlite3
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT_DIR))

from src.model.item import Item  # noqa: E402
from src.model.tfidf_engine import TFIDFRecommendationEngine  # noqa: E402

DB_PATH = ROOT_DIR / "data" / "swayp.db"


def _row_to_item(row: sqlite3.Row) -> Item:
    return Item(
        external_id=row["external_id"],
        domain=row["domain"],
        title=row["title"],
        description=row["description"] or "",
        text_for_vectorization=row["text_for_vectorization"] or "",
        tags=json.loads(row["tags"]) if row["tags"] else [],
        community_score=row["community_score"] or 0.0,
        image_url=row["image_url"],
        external_url=row["external_url"],
        adapter_version=row["adapter_version"],
        enrichment_version=row["enrichment_version"],
    )


def load_catalog(conn: sqlite3.Connection) -> list[Item]:
    rows = conn.execute("SELECT * FROM items").fetchall()
    return [_row_to_item(row) for row in rows]


def find_liked_items(catalog: list[Item], likes: list[str]) -> tuple[list[Item], list[str]]:
    """Búsqueda flexible por substring (case-insensitive), no exacta estricta."""
    found: list[Item] = []
    not_found: list[str] = []
    for like in likes:
        needle = like.strip().lower()
        match = next((item for item in catalog if needle in item.title.lower()), None)
        if match is not None:
            found.append(match)
        else:
            not_found.append(like)
    return found, not_found


def main() -> None:
    parser = argparse.ArgumentParser(description="Recomendaciones de validación manual (Fase 0)")
    parser.add_argument("--user", required=True, help="Nombre del usuario de prueba")
    parser.add_argument("--likes", nargs="+", required=True, help="Títulos que le gustan al usuario")
    parser.add_argument("--top", type=int, default=10, help="Número de recomendaciones a mostrar")
    args = parser.parse_args()

    if not DB_PATH.exists():
        print(f"No se encontró {DB_PATH}. Ejecuta antes scripts/populate_catalog.py")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    catalog = load_catalog(conn)
    conn.close()

    if not catalog:
        print("El catálogo está vacío. Ejecuta scripts/populate_catalog.py primero.")
        sys.exit(1)

    liked_items, not_found = find_liked_items(catalog, args.likes)

    if not_found:
        print(f"No se encontraron estos títulos: {', '.join(not_found)}")

    if not liked_items:
        print("No se encontró ninguno de los títulos indicados en el catálogo.")
        sys.exit(1)

    engine = TFIDFRecommendationEngine()
    recommendations = engine.recommend(liked_items, catalog, top_n=args.top)

    print(f"Usuario: {args.user}")
    print(f"Le gustó: {', '.join(item.title for item in liked_items)}")
    print()
    print("Recomendaciones:")
    for i, (item, score) in enumerate(recommendations, start=1):
        print(f"{i}. {item.title} (score: {score:.2f})")


if __name__ == "__main__":
    main()
