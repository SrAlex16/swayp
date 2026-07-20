# src/adapters/tmdb_adapter.py
import logging
import time

import requests

from src.adapters.base_adapter import BaseAdapter
from src.core.config import config
from src.model.item import Item

logger = logging.getLogger(__name__)

# Plantilla de text_for_vectorization (ver docs/ARCHITECTURE.md, sección 3.1, y
# docs/decisions/0003-normalizacion-de-tags-heterogeneos.md): título + géneros +
# keywords + colección (si aplica) + tagline + sinopsis truncada a ~500 caracteres.
# A diferencia de RAWG, TMDB no mezcla metadatos de plataforma/tienda dentro de sus
# tags: adult/video/softcore/budget/runtime/production_companies... llegan en campos
# separados y simplemente no se usan aquí — no hace falta ningún TAG_DENYLIST para
# este adapter (ver la sesión de inspección de scripts/inspect_tmdb.py).
DESCRIPTION_MAX_CHARS = 500


class TmdbAdapter(BaseAdapter):
    BASE_URL = "https://api.themoviedb.org/3"
    DOMAIN = "movies"
    ADAPTER_VERSION = "tmdb-0.1"
    # Misma versión que RawgAdapter: la lógica de enriquecimiento es conceptualmente
    # equivalente (título + señal estructurada repetida x3 + sinopsis truncada), solo
    # cambian las fuentes de la señal estructurada (genres/tags en RAWG vs.
    # genres/keywords/colección/tagline en TMDB). Si el patrón de un adapter futuro
    # dejara de ser comparable a este esquema, versionar aparte en ese momento.
    ENRICHMENT_VERSION = "enrich-0.1"
    DEFAULT_REQUEST_DELAY_SECONDS = 0.25

    # Nº de veces que se repiten los bloques de géneros/keywords/colección antes de la
    # sinopsis: mismo motivo que GENRE_TAGS_REPEAT en RawgAdapter — la sinopsis libre
    # tiene más palabras que la señal estructurada y la diluye en el recuento TF-IDF.
    STRUCTURED_SIGNAL_REPEAT = 3

    def __init__(
        self,
        api_read_access_token: str | None = None,
        request_delay_seconds: float | None = None,
    ):
        self.api_read_access_token = api_read_access_token or config.tmdb_api_read_access_token
        if not self.api_read_access_token:
            raise ValueError("TMDB_API_READ_ACCESS_TOKEN no está definida (revisa tu .env)")
        self.request_delay_seconds = (
            request_delay_seconds
            if request_delay_seconds is not None
            else self.DEFAULT_REQUEST_DELAY_SECONDS
        )

    def fetch_popular(self, count: int) -> list[Item]:
        logger.info(
            "descargando catálogo popular de TMDB",
            extra={"layer": "adapter", "event": "fetch_popular_started", "count": count},
        )

        items: list[Item] = []
        page = 1

        while len(items) < count:
            listing = self._get("/movie/popular", params={"page": page})
            if listing is None:
                break

            results = listing.get("results", [])
            if not results:
                break

            for movie in results:
                if len(items) >= count:
                    break
                if movie.get("adult"):
                    logger.debug(
                        "película adult=true excluida del catálogo",
                        extra={"layer": "adapter", "event": "adult_item_skipped", "external_id": movie.get("id")},
                    )
                    continue
                item = self.fetch_by_id(str(movie["id"]))
                if item is not None:
                    items.append(item)

            total_pages = listing.get("total_pages", page)
            if page >= total_pages:
                break
            page += 1

        logger.info(
            "catálogo popular de TMDB descargado",
            extra={
                "layer": "adapter",
                "event": "fetch_popular_done",
                "requested": count,
                "obtained": len(items),
            },
        )
        return items

    def fetch_by_id(self, external_id: str) -> Item | None:
        data = self._get(f"/movie/{external_id}", params={"append_to_response": "keywords"})
        if data is None:
            return None
        if data.get("adult"):
            # Excluidas del catálogo, ver decisión en el prompt de este bloque.
            return None
        return self._to_item(data)

    def _get(self, path: str, params: dict | None = None) -> dict | None:
        logger.debug(
            "petición a TMDB", extra={"layer": "adapter", "event": "external_request", "path": path}
        )
        time.sleep(self.request_delay_seconds)
        url = f"{self.BASE_URL}{path}"
        headers = {
            "Authorization": f"Bearer {self.api_read_access_token}",
            "accept": "application/json",
        }
        try:
            response = requests.get(url, headers=headers, params=params, timeout=10)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as exc:
            logger.warning(
                "TMDB: fallo al pedir %s: %s",
                path,
                exc,
                extra={"layer": "adapter", "event": "external_request_failed", "path": path},
            )
            return None

    def _to_item(self, data: dict) -> Item:
        genres = [g["name"] for g in data.get("genres") or []]
        keywords = [k["name"] for k in (data.get("keywords") or {}).get("keywords") or []]
        collection = data.get("belongs_to_collection")
        collection_name = collection.get("name") if collection else None
        description = (data.get("overview") or "").strip()
        tagline = (data.get("tagline") or "").strip()

        vote_average = data.get("vote_average") or 0.0  # TMDB usa escala 0-10
        community_score = max(0.0, min(1.0, vote_average / 10.0))

        poster_path = data.get("poster_path")
        image_url = f"https://image.tmdb.org/t/p/w500{poster_path}" if poster_path else None

        return Item(
            external_id=str(data.get("id")),
            domain=self.DOMAIN,
            title=data.get("title", ""),
            description=description,
            text_for_vectorization=self._build_text_for_vectorization(
                title=data.get("title", ""),
                genres=genres,
                keywords=keywords,
                collection_name=collection_name,
                tagline=tagline,
                description=description,
            ),
            tags=genres + keywords,
            community_score=community_score,
            image_url=image_url,
            external_url=f"https://www.themoviedb.org/movie/{data.get('id')}",
            adapter_version=self.ADAPTER_VERSION,
            enrichment_version=self.ENRICHMENT_VERSION,
        )

    @classmethod
    def _build_text_for_vectorization(
        cls,
        title: str,
        genres: list[str],
        keywords: list[str],
        collection_name: str | None,
        tagline: str,
        description: str,
    ) -> str:
        truncated_description = description[:DESCRIPTION_MAX_CHARS]
        genres_block = " ".join(genres)
        keywords_block = " ".join(keywords)

        parts = [title]
        parts += [genres_block] * cls.STRUCTURED_SIGNAL_REPEAT
        parts += [keywords_block] * cls.STRUCTURED_SIGNAL_REPEAT
        if collection_name:
            parts += [collection_name] * cls.STRUCTURED_SIGNAL_REPEAT
        parts += [tagline, truncated_description]

        return " ".join(part for part in parts if part)
