# src/model/tfidf_engine.py
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

MAX_SVD_COMPONENTS = 100


class TFIDFRecommendationEngine(RecommendationEngine):
    """TF-IDF + SVD + similitud coseno, primera implementación de RecommendationEngine."""

    def recommend(
        self, liked_items: list[Item], catalog: list[Item], top_n: int
    ) -> list[tuple[Item, float]]:
        if not liked_items:
            raise ValueError("liked_items no puede estar vacío")
        if not catalog:
            return []

        corpus = [item.text_for_vectorization for item in catalog]
        vectorizer = TfidfVectorizer(stop_words="english")
        tfidf_matrix = vectorizer.fit_transform(corpus)

        n_components = min(MAX_SVD_COMPONENTS, min(tfidf_matrix.shape) - 1)
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

        liked_indices_set = set(liked_indices)
        scored: list[tuple[Item, float]] = []
        for i, item in enumerate(catalog):
            if i in liked_indices_set:
                continue
            score = SIMILARITY_WEIGHT * similarities[i] + COMMUNITY_SCORE_WEIGHT * item.community_score
            scored.append((item, float(score)))

        scored.sort(key=lambda pair: pair[1], reverse=True)
        return scored[:top_n]
