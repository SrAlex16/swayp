# Changelog

Registro cronológico de avances. Formato: fecha, tipo de cambio, descripción breve.

## [Sin publicar]

### Añadido
- Estructura inicial de documentación en `docs/`.
- Fase 0 del motor de recomendación (sin API REST ni Flutter): `Item` genérico (`src/model/item.py`), interfaz `RecommendationEngine` (`src/model/engine.py`) y su primera implementación `TFIDFRecommendationEngine` (TF-IDF + SVD + similitud coseno, con techo de peso de comunidad al 15%); interfaz `base_adapter.py` y `RawgAdapter` para el dominio de videojuegos (vía API de RAWG); script `scripts/populate_catalog.py` para poblar `data/swayp.db`; CLI `recommend.py` para validación manual de recomendaciones. Validado con 3 perfiles de prueba distintos sobre un catálogo real de 200 juegos.
