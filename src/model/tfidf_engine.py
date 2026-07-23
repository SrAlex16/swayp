# src/model/tfidf_engine.py
import logging
from dataclasses import dataclass

import numpy as np
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from src.model.engine import RecommendationEngine
from src.model.item import Item

logger = logging.getLogger(__name__)

# Techo del peso de comunidad, ver docs/ARCHITECTURE.md sección 9 ("w_community
# tiene techo fijo, nunca domina"): sin límite, el score de comunidad acaba
# ganando siempre a la similitud real con el usuario.
COMMUNITY_SCORE_WEIGHT = 0.15
SIMILARITY_WEIGHT = 1.0 - COMMUNITY_SCORE_WEIGHT

# Techo de vocabulario del TF-IDF: sin límite, el vocabulario real de un catálogo de
# unos pocos cientos de ítems puede llegar a varios miles de términos, muchos de ellos
# idiosincráticos de una sola sinopsis (nombres propios, frases sueltas...) que acaban
# pesando en la similitud tanto como términos de género realmente compartidos entre
# ítems. TfidfVectorizer ya limita esto a min(MAX_TFIDF_FEATURES, vocabulario_real), así
# que no hace nada si el catálogo es pequeño y el vocabulario real no llega al techo.
MAX_TFIDF_FEATURES = 2000

# Techo de frecuencia de documento: descarta términos que aparecen en más de la mitad
# del catálogo (p. ej. "steam", "game", "player" en un catálogo de videojuegos). Con
# pocos ítems, un término casi universal no aporta señal de género/temática — solo
# diluye el peso de los términos que sí distinguen unos ítems de otros.
MAX_DOCUMENT_FREQUENCY = 0.5

# Nº de componentes SVD como fracción del tamaño del catálogo: con casi tantas
# componentes como documentos, el SVD memoriza peculiaridades de sinopsis individuales
# (ruido textual) en vez de extraer patrones de género/tags compartidos entre varios
# ítems — es sobreajuste, no señal. MIN_SVD_COMPONENTS evita quedarse con muy pocas
# componentes en catálogos pequeños; MAX_SVD_COMPONENTS sigue siendo el techo para
# cuando el catálogo crezca a miles de ítems.
SVD_COMPONENTS_PER_ITEM = 5  # como mucho catálogo/5 componentes
MIN_SVD_COMPONENTS = 10
MAX_SVD_COMPONENTS = 100

DEFAULT_SHARED_TERMS = 8

# Nº de veces que se repite cada tag de una preferencia explícita al construir el
# documento sintético que representa el perfil declarado (ver _build_explicit_text).
EXPLICIT_PREFERENCE_REPEAT_FACTOR = 3

# Techo del nº de señales fuertes (known_liked/known_disliked) a partir del cual el
# peso se desplaza por completo hacia el vector implícito — ver docs/ARCHITECTURE.md
# sección 9 ("w_explicit = max(0.1, 1 - swipes/50)").
STRONG_SIGNAL_SHRINKAGE_CEILING = 50
MIN_EXPLICIT_WEIGHT = 0.1


@dataclass
class ScoredItem:
    """Desglose de una recomendación, ver TFIDFRecommendationEngine.recommend_with_breakdown."""

    item: Item
    final_score: float
    similarity_score: float
    community_score: float
    shared_terms: list[tuple[str, float]] | None = None


class TFIDFRecommendationEngine(RecommendationEngine):
    """TF-IDF + SVD + similitud coseno, primera implementación de RecommendationEngine."""

    # Qué versión de esta implementación generó una recomendación concreta, para
    # trazabilidad (se guarda en jobs.engine_version, ver docs/ARCHITECTURE.md 3.3).
    ENGINE_VERSION = "tfidf-0.1"

    def recommend(
        self,
        rated_items: list[tuple[Item, float]],
        catalog: list[Item],
        top_n: int,
        explicit_preferences: list[tuple[str, float]] | None = None,
        strong_signal_count: int = 0,
    ) -> list[tuple[Item, float]]:
        scored = self._score_catalog(
            rated_items,
            catalog,
            explicit_preferences=explicit_preferences,
            strong_signal_count=strong_signal_count,
        )
        scored.sort(key=lambda entry: entry.final_score, reverse=True)
        return [(entry.item, entry.final_score) for entry in scored[:top_n]]

    def recommend_with_breakdown(
        self,
        liked_items: list[Item],
        catalog: list[Item],
        top_n: int,
        shared_terms: int = DEFAULT_SHARED_TERMS,
    ) -> list[ScoredItem]:
        """Como recommend(), pero desglosando similarity_score/community_score y los
        términos TF-IDF que cada recomendación comparte con el perfil (uso: --debug en
        recommend.py). Trata cada ítem de liked_items como señal positiva de peso 1.0
        — recommend.py todavía no tiene concepto de señales negativas ni de
        preferencias explícitas."""
        rated_items = [(item, 1.0) for item in liked_items]
        scored = self._score_catalog(rated_items, catalog, shared_terms=shared_terms)
        scored.sort(key=lambda entry: entry.final_score, reverse=True)
        return scored[:top_n]

    def _score_catalog(
        self,
        rated_items: list[tuple[Item, float]],
        catalog: list[Item],
        shared_terms: int | None = None,
        explicit_preferences: list[tuple[str, float]] | None = None,
        strong_signal_count: int = 0,
    ) -> list[ScoredItem]:
        if not rated_items:
            raise ValueError("rated_items no puede estar vacío")
        if not catalog:
            return []

        corpus = [item.text_for_vectorization for item in catalog]

        # Si hay preferencias explícitas, se añade su texto sintético como UN
        # documento más al final del corpus antes de fit_transform: así cae en el
        # mismo espacio SVD que el catálogo sin necesitar un transform() aparte. Su
        # índice es len(catalog) (el último).
        explicit_row_index: int | None = None
        if explicit_preferences:
            corpus = corpus + [
                self._build_explicit_preferences_text(explicit_preferences)
            ]
            explicit_row_index = len(catalog)

        vectorizer = TfidfVectorizer(
            stop_words="english",
            max_features=MAX_TFIDF_FEATURES,
            max_df=MAX_DOCUMENT_FREQUENCY,
        )
        tfidf_matrix = vectorizer.fit_transform(corpus)

        # Se calcula sobre len(catalog), no sobre len(corpus): el nº de componentes no
        # debe depender de si el usuario declaró preferencias explícitas o no.
        target_components = max(
            MIN_SVD_COMPONENTS,
            min(MAX_SVD_COMPONENTS, len(catalog) // SVD_COMPONENTS_PER_ITEM),
        )
        n_components = min(target_components, min(tfidf_matrix.shape) - 1)
        if n_components < 1:
            # Catálogo/vocabulario demasiado pequeño para SVD; se usa TF-IDF crudo.
            latent_matrix = tfidf_matrix.toarray()
        else:
            svd = TruncatedSVD(n_components=n_components, random_state=42)
            latent_matrix = svd.fit_transform(tfidf_matrix)

        weight_by_key = {
            (item.domain, item.external_id): weight for item, weight in rated_items
        }
        rated_indices_weights = [
            (i, weight_by_key[(item.domain, item.external_id)])
            for i, item in enumerate(catalog)
            if (item.domain, item.external_id) in weight_by_key
        ]
        if not rated_indices_weights:
            raise ValueError("Ninguno de los rated_items está presente en el catalog")

        rated_indices = [i for i, _ in rated_indices_weights]
        rated_indices_set = set(rated_indices)
        weights = np.array([w for _, w in rated_indices_weights], dtype=float)
        abs_weight_sum = float(np.sum(np.abs(weights)))

        if abs_weight_sum == 0:
            # No hay forma de construir un vector de perfil (todos los pesos se
            # cancelan o son 0): se degrada a ordenar por community_score, que sigue
            # siendo una señal válida aunque no haya afinidad de contenido que medir.
            # Las preferencias explícitas no entran en este fallback (no hay vector
            # implícito con el que mezclarlas).
            logger.warning(
                "suma de pesos absolutos de rated_items es 0; no se puede construir "
                "un vector de perfil, se ordena el catálogo solo por community_score",
                extra={
                    "layer": "model",
                    "event": "zero_weight_profile_fallback",
                    "rated_count": len(rated_items),
                },
            )
            return [
                ScoredItem(
                    item=item,
                    final_score=float(item.community_score),
                    similarity_score=0.0,
                    community_score=float(item.community_score),
                    shared_terms=[] if shared_terms else None,
                )
                for i, item in enumerate(catalog)
                if i not in rated_indices_set
            ]

        implicit_vector = (
            np.sum(
                latent_matrix[rated_indices] * weights[:, None], axis=0, keepdims=True
            )
            / abs_weight_sum
        )

        if explicit_row_index is not None:
            explicit_vector = latent_matrix[explicit_row_index : explicit_row_index + 1]
            w_explicit = max(
                MIN_EXPLICIT_WEIGHT,
                1 - strong_signal_count / STRONG_SIGNAL_SHRINKAGE_CEILING,
            )
            w_implicit = 1 - w_explicit
            profile_vector = w_implicit * implicit_vector + w_explicit * explicit_vector
            logger.debug(
                "shrinkage aplicado: mezclando vector implícito y preferencias explícitas",
                extra={
                    "layer": "model",
                    "event": "explicit_preferences_shrinkage",
                    "w_implicit": w_implicit,
                    "w_explicit": w_explicit,
                    "strong_signal_count": strong_signal_count,
                },
            )
        else:
            profile_vector = implicit_vector

        # Las similitudes se calculan solo contra las filas del catálogo real: la fila
        # sintética de preferencias explícitas (si existe) no es un Item recomendable.
        catalog_latent_matrix = latent_matrix[: len(catalog)]
        similarities = cosine_similarity(profile_vector, catalog_latent_matrix)[0]

        # Los términos compartidos se calculan en el espacio TF-IDF crudo (antes de
        # SVD): las componentes de SVD son combinaciones lineales del vocabulario, no
        # mapean a términos concretos, así que no sirven para "explicar" con palabras.
        # Se calculan solo a partir de rated_indices (implícito), no de la fila
        # sintética de preferencias explícitas.
        feature_names = None
        profile_tfidf_row = None
        if shared_terms:
            feature_names = vectorizer.get_feature_names_out()
            rated_tfidf_rows = tfidf_matrix[rated_indices].toarray()
            profile_tfidf_row = (
                np.sum(rated_tfidf_rows * weights[:, None], axis=0) / abs_weight_sum
            )

        scored: list[ScoredItem] = []
        for i, item in enumerate(catalog):
            if i in rated_indices_set:
                continue

            similarity_score = float(similarities[i])
            community_score = float(item.community_score)
            final_score = (
                SIMILARITY_WEIGHT * similarity_score
                + COMMUNITY_SCORE_WEIGHT * community_score
            )

            shared: list[tuple[str, float]] | None = None
            if shared_terms:
                item_tfidf_row = tfidf_matrix[i].toarray().ravel()
                shared = self._top_shared_terms(
                    feature_names, profile_tfidf_row, item_tfidf_row, shared_terms
                )

            scored.append(
                ScoredItem(
                    item=item,
                    final_score=final_score,
                    similarity_score=similarity_score,
                    community_score=community_score,
                    shared_terms=shared,
                )
            )

        return scored

    @staticmethod
    def _build_explicit_preferences_text(
        explicit_preferences: list[tuple[str, float]],
    ) -> str:
        """Construye el documento sintético que representa las preferencias
        declaradas: cada tag se repite round(max(1, peso * 3)) veces, para que su
        peso relativo en el TF-IDF sea proporcional al peso declarado sin necesitar
        una vectorización distinta del resto del catálogo."""
        parts: list[str] = []
        for tag, weight in explicit_preferences:
            repeat_count = round(max(1, weight * EXPLICIT_PREFERENCE_REPEAT_FACTOR))
            parts.extend([tag] * repeat_count)
        return " ".join(parts)

    @staticmethod
    def _top_shared_terms(
        feature_names: np.ndarray,
        profile_row: np.ndarray,
        item_row: np.ndarray,
        top_n: int,
    ) -> list[tuple[str, float]]:
        """Términos con mayor contribución (profile_weight * item_weight) al solape
        TF-IDF entre el perfil y el ítem."""
        contributions = profile_row * item_row
        shared_indices = np.nonzero(contributions > 0)[0]
        if shared_indices.size == 0:
            return []
        top_indices = shared_indices[
            np.argsort(contributions[shared_indices])[::-1][:top_n]
        ]
        return [
            (str(feature_names[idx]), float(contributions[idx])) for idx in top_indices
        ]
