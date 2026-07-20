# src/adapters/rawg_adapter.py
import logging
import time

import requests

from src.adapters.base_adapter import BaseAdapter
from src.core.config import config
from src.model.item import Item

logger = logging.getLogger(__name__)

# Plantilla de text_for_vectorization (ver docs/ARCHITECTURE.md, sección 3.1):
# título + géneros + top-N tags + sinopsis truncada a ~500 caracteres. RAWG da
# poco texto libre y muchos tags/géneros, así que se limita cuánto de cada
# fuente entra, para que la señal sea comparable a la de adapters con sinopsis
# más largas (TMDB, Open Library...).
DESCRIPTION_MAX_CHARS = 500
MAX_TAGS = 10

# Metadatos de plataforma/tienda y características técnicas del juego a excluir del
# texto que entra al TF-IDF (no del campo `tags` de Item, que sigue mostrando todos los
# tags sin filtrar para la UI): describen dónde/cómo se distribuye, se juega o con
# cuánta gente, no el género o la temática del título, y con GENRE_TAGS_REPEAT
# repitiendo el bloque de tags x3 su presencia o ausencia pesaba desproporcionadamente.
# Caso real detectado: Bloodborne (exclusivo de PlayStation, sin ningún tag de Steam)
# perdía peso relativo de género frente a Terraria/Cuphead (con "Steam Achievements",
# "Steam Cloud"... entre sus tags), cuyo ruido de plataforma se multiplicaba x3 mientras
# Bloodborne no tenía nada que repetir en su lugar. "Co-op"/"Multiplayer"/"Singleplayer"
# se suman por el mismo motivo (modo de juego, no género) más un problema de
# tokenización: el guion en "Co-op" se separa en "co"+"op" sueltos, ruido adicional.
TAG_DENYLIST = frozenset(
    tag.lower()
    for tag in (
        "Steam Achievements",
        "Steam Cloud",
        "Steam Leaderboards",
        "Steam Workshop",
        "Valve Anti-Cheat enabled",
        "steam-trading-cards",
        "Full controller support",
        "Partial Controller Support",
        "controller support",
        "Controller",
        "Cross-Platform Multiplayer",
        "Captions available",
        "exclusive",
        "true exclusive",
        "vr mod",
        "Free to Play",
        "In-App Purchases",
        "Co-op",
        "Cooperative",
        "Multiplayer",
        "Singleplayer",
    )
)


class RawgAdapter(BaseAdapter):
    BASE_URL = "https://api.rawg.io/api"
    DOMAIN = "games"
    ADAPTER_VERSION = "rawg-0.1"
    ENRICHMENT_VERSION = "enrich-0.1"
    PAGE_SIZE = 40
    DEFAULT_REQUEST_DELAY_SECONDS = 0.25

    def __init__(self, api_key: str | None = None, request_delay_seconds: float | None = None):
        self.api_key = api_key or config.rawg_api_key
        if not self.api_key:
            raise ValueError("RAWG_API_KEY no está definida (revisa tu .env)")
        self.request_delay_seconds = (
            request_delay_seconds
            if request_delay_seconds is not None
            else self.DEFAULT_REQUEST_DELAY_SECONDS
        )

    def fetch_popular(self, count: int) -> list[Item]:
        logger.info(
            "descargando catálogo popular de RAWG",
            extra={"layer": "adapter", "event": "fetch_popular_started", "count": count},
        )

        items: list[Item] = []
        page = 1
        page_size = min(self.PAGE_SIZE, max(1, count))

        while len(items) < count:
            listing = self._get(
                "/games",
                params={"ordering": "-added", "page": page, "page_size": page_size},
            )
            if listing is None:
                break

            results = listing.get("results", [])
            if not results:
                break

            for game in results:
                if len(items) >= count:
                    break
                item = self.fetch_by_id(str(game["id"]))
                if item is not None:
                    items.append(item)

            if not listing.get("next"):
                break
            page += 1

        logger.info(
            "catálogo popular de RAWG descargado",
            extra={
                "layer": "adapter",
                "event": "fetch_popular_done",
                "requested": count,
                "obtained": len(items),
            },
        )
        return items

    def fetch_by_id(self, external_id: str) -> Item | None:
        data = self._get(f"/games/{external_id}")
        if data is None:
            return None
        return self._to_item(data)

    def _get(self, path: str, params: dict | None = None) -> dict | None:
        logger.debug(
            "petición a RAWG", extra={"layer": "adapter", "event": "external_request", "path": path}
        )
        time.sleep(self.request_delay_seconds)
        url = f"{self.BASE_URL}{path}"
        query = {"key": self.api_key, **(params or {})}
        try:
            response = requests.get(url, params=query, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as exc:
            logger.warning(
                "RAWG: fallo al pedir %s: %s",
                path,
                exc,
                extra={"layer": "adapter", "event": "external_request_failed", "path": path},
            )
            return None

    def _to_item(self, data: dict) -> Item:
        genres = [g["name"] for g in data.get("genres") or []]
        tags = [t["name"] for t in (data.get("tags") or [])[:MAX_TAGS]]
        description = (data.get("description_raw") or "").strip()

        rating = data.get("rating") or 0.0  # RAWG usa escala 0-5
        community_score = max(0.0, min(1.0, rating / 5.0))

        slug = data.get("slug")
        external_url = f"https://rawg.io/games/{slug}" if slug else None

        vectorization_tags = [tag for tag in tags if tag.lower() not in TAG_DENYLIST]

        return Item(
            external_id=str(data.get("id")),
            domain=self.DOMAIN,
            title=data.get("name", ""),
            description=description,
            text_for_vectorization=self._build_text_for_vectorization(
                title=data.get("name", ""),
                genres=genres,
                tags=vectorization_tags,
                description=description,
            ),
            tags=genres + tags,
            community_score=community_score,
            image_url=data.get("background_image"),
            external_url=external_url,
            adapter_version=self.ADAPTER_VERSION,
            enrichment_version=self.ENRICHMENT_VERSION,
        )

    # Nº de veces que se repite el bloque de géneros/tags antes de la sinopsis: la
    # sinopsis libre (hasta 500 caracteres) tiene muchas más palabras que la lista de
    # géneros/tags, así que en el recuento de términos del TF-IDF la prosa domina y la
    # señal estructurada de género queda diluida. Repetir el bloque multiplica su peso
    # en la matriz de términos para que compita con la sinopsis en vez de perderse en ella.
    GENRE_TAGS_REPEAT = 3

    @staticmethod
    def _build_text_for_vectorization(
        title: str, genres: list[str], tags: list[str], description: str
    ) -> str:
        truncated_description = description[:DESCRIPTION_MAX_CHARS]
        genre_tags_block = " ".join(genres + tags)
        parts = [title] + [genre_tags_block] * RawgAdapter.GENRE_TAGS_REPEAT + [truncated_description]
        return " ".join(part for part in parts if part)
