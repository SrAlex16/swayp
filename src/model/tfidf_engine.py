# src/model/tfidf_engine.py
from dataclasses import dataclass

import numpy as np
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from src.model.engine import RecommendationEngine
from src.model.item import Item

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

    def recommend(
        self, liked_items: list[Item], catalog: list[Item], top_n: int
    ) -> list[tuple[Item, float]]:
        scored = self._score_catalog(liked_items, catalog)
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
        recommend.py)."""
        scored = self._score_catalog(liked_items, catalog, shared_terms=shared_terms)
        scored.sort(key=lambda entry: entry.final_score, reverse=True)
        return scored[:top_n]

    def _score_catalog(
        self,
        liked_items: list[Item],
        catalog: list[Item],
        shared_terms: int | None = None,
    ) -> list[ScoredItem]:
        if not liked_items:
            raise ValueError("liked_items no puede estar vacío")
        if not catalog:
            return []

        corpus = [item.text_for_vectorization for item in catalog]
        vectorizer = TfidfVectorizer(
            stop_words="english", max_features=MAX_TFIDF_FEATURES, max_df=MAX_DOCUMENT_FREQUENCY
        )
        tfidf_matrix = vectorizer.fit_transform(corpus)

        target_components = max(
            MIN_SVD_COMPONENTS, min(MAX_SVD_COMPONENTS, len(catalog) // SVD_COMPONENTS_PER_ITEM)
        )
        n_components = min(target_components, min(tfidf_matrix.shape) - 1)
        if n_components < 1:
            # Catálogo/vocabulario demasiado pequeño para SVD; se usa TF-IDF crudo.
            latent_matrix = tfidf_matrix.toarray()
        else:
            svd = TruncatedSVD(n_components=n_components, random_state=42)
            latent_matrix = svd.fit_transform(tfidf_matrix)

        liked_keys = {(item.domain, item.external_id) for item in liked_items}
        liked_indices = [
            i for i, item in enumerate(catalog) if (item.domain, item.external_id) in liked_keys
        ]
        if not liked_indices:
            raise ValueError("Ninguno de los liked_items está presente en el catalog")

        profile_vector = latent_matrix[liked_indices].mean(axis=0, keepdims=True)
        similarities = cosine_similarity(profile_vector, latent_matrix)[0]

        # Los términos compartidos se calculan en el espacio TF-IDF crudo (antes de
        # SVD): las componentes de SVD son combinaciones lineales del vocabulario, no
        # mapean a términos concretos, así que no sirven para "explicar" con palabras.
        feature_names = None
        profile_tfidf_row = None
        if shared_terms:
            feature_names = vectorizer.get_feature_names_out()
            profile_tfidf_row = np.asarray(tfidf_matrix[liked_indices].mean(axis=0)).ravel()

        liked_indices_set = set(liked_indices)
        scored: list[ScoredItem] = []
        for i, item in enumerate(catalog):
            if i in liked_indices_set:
                continue

            similarity_score = float(similarities[i])
            community_score = float(item.community_score)
            final_score = SIMILARITY_WEIGHT * similarity_score + COMMUNITY_SCORE_WEIGHT * community_score

            shared: list[tuple[str, float]] | None = None
            if shared_terms:
                item_tfidf_row = tfidf_matrix[i].toarray().ravel()
                shared = self._top_shared_terms(feature_names, profile_tfidf_row, item_tfidf_row, shared_terms)

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
        top_indices = shared_indices[np.argsort(contributions[shared_indices])[::-1][:top_n]]
        return [(str(feature_names[idx]), float(contributions[idx])) for idx in top_indices]
