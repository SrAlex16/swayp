# Changelog

Registro cronológico de avances. Formato: fecha, tipo de cambio, descripción breve.

## [Sin publicar]

### Añadido
- Estructura inicial de documentación en `docs/`.
- Fase 0 del motor de recomendación (sin API REST ni Flutter): `Item` genérico (`src/model/item.py`), interfaz `RecommendationEngine` (`src/model/engine.py`) y su primera implementación `TFIDFRecommendationEngine` (TF-IDF + SVD + similitud coseno, con techo de peso de comunidad al 15%); interfaz `base_adapter.py` y `RawgAdapter` para el dominio de videojuegos (vía API de RAWG); script `scripts/populate_catalog.py` para poblar `data/swayp.db`; CLI `recommend.py` para validación manual de recomendaciones. Validado con 3 perfiles de prueba distintos sobre un catálogo real de 200 juegos.

### Cambiado
- Limpieza de restos del proyecto anterior (Anime Recommender) para evitar confusión durante el desarrollo de Swayp. Eliminados: pipeline de datos y motor de anime (`src/data/`, `src/model/train_model.py`, `src/services/`, `src/api/app.py`), datasets de anime en `data/` y el runner Dart vestigial (`python_runner.dart`). Archivados como referencia (no ejecutable/mantenida) en `legacy_reference/`: pantallas y servicios Flutter del proyecto anterior (login, recomendaciones, blacklist) y `notebooks/`. `README.md` reescrito para reflejar Swayp. `requirements.txt`: eliminada `tqdm` (solo la usaba el script de anime eliminado); `flask`/`flask-cors`/`gunicorn` se mantienen sin uso actual, se necesitarán en la Fase 1.
- Completada la limpieza: `background_img.png` y `lib/main.dart` movidos a `legacy_reference/frontend/anime_recommender_app/` junto al resto del frontend legacy (el `lib/` activo queda vacío hasta la reescritura de la Fase 3). Eliminados los tests que probaban el pipeline de anime ya borrado (`src/tests/test_fetch_datasets.py`, `test_parse_xml.py`, `test_train_model.py`, `test_prepare_data.py`, `test_pipeline.py`, `run_tests.py`). `build.sh` ya no invoca `preload_dataset.py` (eliminado), queda un TODO para reescribirlo en la Fase 1. `requirements.txt`: eliminadas `matplotlib` y `tabulate`, sin uso en el repo tras la limpieza.
