# recommend.py
"""CLI de validación manual del motor de recomendación (Fase 0, ver docs/TODO.md).

Uso:
    python recommend.py --user test --likes "Elden Ring" "Dark Souls" "Hollow Knight"
    python recommend.py --user test --likes "Elden Ring" "Dark Souls" --debug
    python recommend.py --domain movies --user test --likes "Moana" "Scary Movie"
    python recommend.py --inspect-text "Elden Ring"
"""
import argparse
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT_DIR))

from src.model.item import Item  # noqa: E402
from src.model.tfidf_engine import TFIDFRecommendationEngine  # noqa: E402
from src.repositories import item_repository  # noqa: E402

DB_PATH = ROOT_DIR / "data" / "swayp.db"
DEFAULT_DOMAIN = "games"


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


def load_catalog_from_db(domain: str) -> list[Item]:
    if not DB_PATH.exists():
        print(f"No se encontró {DB_PATH}. Ejecuta antes scripts/populate_catalog.py")
        sys.exit(1)

    catalog = item_repository.get_all(domain)

    if not catalog:
        print(f"El catálogo de '{domain}' está vacío. Ejecuta antes scripts/populate_catalog.py --domain {domain}")
        sys.exit(1)

    return catalog


def inspect_text(domain: str, title_query: str) -> None:
    """Imprime el text_for_vectorization guardado tal cual, sin pasar por el motor."""
    catalog = load_catalog_from_db(domain)
    needle = title_query.strip().lower()
    match = next((item for item in catalog if needle in item.title.lower()), None)

    if match is None:
        print(f"No se encontró ningún título que contenga: {title_query}")
        sys.exit(1)

    print(f"Título: {match.title}")
    print("text_for_vectorization:")
    print(match.text_for_vectorization)


def main() -> None:
    parser = argparse.ArgumentParser(description="Recomendaciones de validación manual (Fase 0)")
    parser.add_argument(
        "--domain",
        default=DEFAULT_DOMAIN,
        help=f"Dominio a usar, ej. 'games' o 'movies' (default: {DEFAULT_DOMAIN})",
    )
    parser.add_argument("--user", help="Nombre del usuario de prueba")
    parser.add_argument("--likes", nargs="+", help="Títulos que le gustan al usuario")
    parser.add_argument("--top", type=int, default=10, help="Número de recomendaciones a mostrar")
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Desglosa similarity_score, community_score_normalizado y términos TF-IDF compartidos",
    )
    parser.add_argument(
        "--inspect-text",
        metavar="TITULO",
        help="Imprime el text_for_vectorization guardado para ese título y sale (sin usar el motor)",
    )
    args = parser.parse_args()

    if args.inspect_text:
        inspect_text(args.domain, args.inspect_text)
        return

    if not args.user or not args.likes:
        parser.error("--user y --likes son obligatorios (salvo que uses --inspect-text)")

    catalog = load_catalog_from_db(args.domain)
    liked_items, not_found = find_liked_items(catalog, args.likes)

    if not_found:
        print(f"No se encontraron estos títulos: {', '.join(not_found)}")

    if not liked_items:
        print("No se encontró ninguno de los títulos indicados en el catálogo.")
        sys.exit(1)

    engine = TFIDFRecommendationEngine()

    print(f"Usuario: {args.user}")
    print(f"Le gustó: {', '.join(item.title for item in liked_items)}")
    print()
    print("Recomendaciones:")

    if args.debug:
        breakdown = engine.recommend_with_breakdown(liked_items, catalog, top_n=args.top)
        for i, entry in enumerate(breakdown, start=1):
            print(f"{i}. {entry.item.title} (score: {entry.final_score:.2f})")
            print(f"   similarity_score: {entry.similarity_score:.3f}")
            print(f"   community_score_normalizado: {entry.community_score:.3f}")
            if entry.shared_terms:
                terms = ", ".join(f"{term} ({weight:.3f})" for term, weight in entry.shared_terms)
                print(f"   términos TF-IDF compartidos: {terms}")
            else:
                print("   términos TF-IDF compartidos: (ninguno)")
    else:
        # recommend.py no tiene concepto de señales negativas: cada like se pasa con
        # peso 1.0 (ver src/model/engine.py para la nueva firma de recommend()).
        rated_items = [(item, 1.0) for item in liked_items]
        recommendations = engine.recommend(rated_items, catalog, top_n=args.top)
        for i, (item, score) in enumerate(recommendations, start=1):
            print(f"{i}. {item.title} (score: {score:.2f})")


if __name__ == "__main__":
    main()
