# scripts/seed_test_rating.py
"""Script CLI TEMPORAL, no documentado como parte permanente de la API: sirve para
sembrar ratings 'interested' de prueba directamente (sin pasar por HTTP) y así poder
probar el flujo de jobs de recomendaciones antes de que exista el endpoint real de
ratings (Bloque C). Se puede borrar en cuanto ese endpoint exista.

Uso:
    python scripts/seed_test_rating.py --device-id test1 --domain games \
        --likes "Elden Ring" "Dark Souls III" "Hollow Knight"
"""
import argparse
import sqlite3
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from src.core.db import init_db  # noqa: E402
from src.model.item import Item  # noqa: E402
from src.repositories import item_repository, rating_repository, user_repository  # noqa: E402


def find_item_by_title(catalog: list[Item], title_query: str) -> Item | None:
    """Búsqueda flexible por substring (case-insensitive), no exacta estricta."""
    needle = title_query.strip().lower()
    return next((item for item in catalog if needle in item.title.lower()), None)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Siembra ratings 'interested' de prueba (script temporal, sin HTTP)"
    )
    parser.add_argument("--device-id", required=True, help="device_id del usuario de prueba")
    parser.add_argument("--domain", required=True, help="Código de dominio, ej. 'games'")
    parser.add_argument("--likes", nargs="+", required=True, help="Títulos a marcar como 'interested'")
    args = parser.parse_args()

    init_db()

    catalog = item_repository.get_all(args.domain)
    if not catalog:
        print(f"No hay ítems para el dominio '{args.domain}'. Ejecuta antes scripts/populate_catalog.py")
        sys.exit(1)

    user = user_repository.get_or_create_by_device_id(args.device_id)

    created: list[str] = []
    already_rated: list[str] = []
    not_found: list[str] = []

    for title in args.likes:
        item = find_item_by_title(catalog, title)
        if item is None:
            not_found.append(title)
            continue
        try:
            rating_repository.create(
                user_id=user.id,
                item_id=item.id,
                domain_code=args.domain,
                status="interested",
                source="onboarding",
            )
            created.append(item.title)
        except sqlite3.IntegrityError:
            already_rated.append(item.title)

    print(f"Usuario: {args.device_id} (id={user.id})")
    if created:
        print(f"Ratings 'interested' creados: {', '.join(created)}")
    if already_rated:
        print(f"Ya tenían rating (sin duplicar): {', '.join(already_rated)}")
    if not_found:
        print(f"No se encontraron estos títulos: {', '.join(not_found)}")


if __name__ == "__main__":
    main()
