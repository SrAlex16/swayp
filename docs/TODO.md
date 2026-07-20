# To-do — corto plazo (Fase 0: validar el motor sin API ni Flutter)

- [x] Definir el modelo `Item` (dataclass/pydantic)
- [x] Implementar `base_adapter.py` (interfaz) y un primer adapter real
- [x] Esquema mínimo de SQLite para `items` (solo lo necesario para esta fase)
- [x] Construir `text_for_vectorization` en el adapter elegido
- [x] Implementar `TFIDFRecommendationEngine` (interfaz `RecommendationEngine` + primera implementación)
- [x] Script `recommend.py` de terminal: usuario de prueba con gustos declarados → top N recomendaciones legibles
- [x] Validar manualmente con 2-3 perfiles de prueba distintos si las recomendaciones tienen sentido
- [x] Decidir si hace falta enriquecer más los datos antes de pasar a la Fase 1 (decidido: no enriquecer más sobre este catálogo de prueba — ver docs/fase0-validacion.md, veredicto final)

**Fase 0 completada.** Próxima fase: Fase 1 (API mínima sobre el dominio de videojuegos) — ver docs/ARCHITECTURE.md, sección Roadmap.

## Fase 1: API mínima sobre el dominio de videojuegos

- [x] Esquema de BD ampliado (`users`, `ratings`, `jobs`) sin tocar `items` (`src/core/db.py`)
- [x] `core/` — config centralizada, conexión SQLite, logging estructurado en JSON, jerarquía de errores
- [x] `repositories/` — user, item, rating, job
- [x] Job asíncrono de generación de recomendaciones (`job_service` + `recommendation_service`, hilo en background) con endpoints `POST /domains/<domain_code>/recommendations/jobs` y `GET /jobs/<job_id>`
- [x] Endpoint `POST /domains/<domain_code>/ratings` (señal simple interested/rejected, sin known_liked/known_disliked todavía — ver Fase 3)
- [x] Endpoint `GET /domains/<domain_code>/seed` (muestreo aleatorio simple; estratificación por género pendiente, ver docs/ROADMAP.md)
- [x] Probar el flujo completo (seed → ratings → job → resultado) contra el servidor Flask real antes de dar la Fase 1 por cerrada (confirmado con curl end-to-end, incluidos los casos de error)

**Fase 1 completada.**

## Fase 2: segundo dominio (películas, TMDB)

- [x] Inspección de datos reales de TMDB antes de construir el adapter (script temporal, borrado tras la inspección — ver docs/decisions/0003-normalizacion-de-tags-heterogeneos.md)
- [x] `TmdbAdapter` (`src/adapters/tmdb_adapter.py`), dominio "movies"
- [x] `--domain` en `scripts/populate_catalog.py` y `recommend.py` (default "games", sin romper el comportamiento existente)
- [x] Validado sin tocar `src/model/`, `src/api/`, `src/services/` — confirma que la arquitectura es extensible de verdad, no solo en el diseño
- [x] Validación manual con 2 perfiles de gustos de cine bien distintos (familia/animación vs. terror) — ambos coherentes y sin mezclarse

**Fase 2 completada.**

## Instrumentación de logging (transversal, no ligada a una fase del roadmap)

- [x] Logs en todas las capas (adapters, servicios, repositories, nivel HTTP) — antes solo `job_service.py` tenía cobertura real
- [x] `request_completed` en `after_request` (método, ruta, status, `duration_ms`) para toda request que se complete, incluida la vía de excepción no controlada
- [x] `errorhandler(Exception)` genérico — antes una excepción no controlada rompía el contrato "siempre JSON" de la API
- [x] Rotación de archivos (`TimedRotatingFileHandler`) + retención configurable por `.env`, sin necesidad de un job de limpieza aparte
- [x] `.env.example` con las 7 variables de entorno del proyecto

**Próxima decisión pendiente**: filtros (`domain_facets`), perfil de usuario, o completar el modelo de señales (`known_liked`/`known_disliked`, toggle 'ya lo conozco') — ver docs/ARCHITECTURE.md, secciones 7-9.
