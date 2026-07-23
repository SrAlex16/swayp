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

## Modelo de señales — capa de API

- [x] `POST /domains/<domain_code>/ratings` acepta los 4 status (`interested`, `rejected`, `known_liked`, `known_disliked`), no solo los 2 de la Fase 1
- [x] `PATCH /domains/<domain_code>/ratings/<rating_id>` para actualizar el status de un rating existente (flujo de confirmación de la pantalla de Guardados, ARCHITECTURE.md sección 7.3)
- [x] `GET /domains/<domain_code>/pending-confirmation` — ratings `interested` sin confirmar, con datos del item para listarlos directamente
- [x] `rating_repository`: `get_by_id`, `get_by_status`, `update_status`
- [x] Validado con curl end-to-end: alta directa en `known_liked`, alta `interested`, aparece en pendientes, `PATCH` a `known_liked`, desaparece de pendientes, y los 2 casos de error (rating inexistente, status inválido)

## Perfil de usuario — capa de API

- [x] `GET /users/profile` — perfil vacío es 200 con `{age: null, gender: null}`, no 404
- [x] `PUT /users/profile` — valida `age` (1-120 si viene), `gender` libre sin validar
- [x] `GET /users/domains/<domain_code>/preferences` — lista vacía si no hay ninguna, no 404
- [x] `PUT /users/domains/<domain_code>/preferences` — reemplaza todas las preferencias del dominio, valida `weight` (0-1)
- [x] Validado con curl end-to-end: perfil nuevo, actualización válida, `age` inválido, preferencias vacías, alta, reemplazo completo (confirmado que no se acumulan), y una recomendación real que refleja `strong_signal_count` y preferencias explícitas en el log

## Registro de dominios

- [x] Tabla `domains` (código, nombre, habilitado) — qué dominios existen, capa de producto/BD
- [x] `src/adapters/registry.py` — qué adapter de Python implementa cada dominio, capa de código; `domain_repository.py` no importa nada de `src/adapters/` y viceversa
- [x] `scripts/populate_catalog.py` usa el registry en vez de su propio diccionario local (comportamiento sin cambios)
- [x] `GET /domains` — lista de dominios habilitados
- [x] Validación de `domain_code` centralizada (`src/api/routes/_shared.py`) y aplicada en las 4 rutas que reciben `<domain_code>` en la URL (jobs, ratings, seed, preferences) — un dominio inexistente ahora da 404 en vez de seguir silenciosamente con un catálogo vacío
- [x] Validado con curl: `GET /domains` devuelve games+movies, `seed` de un dominio real sigue igual, `seed` de un dominio inventado da 404, `populate_catalog.py` sin `--domain` sigue funcionando igual tras el refactor

## CI/CD

- [x] `ruff` añadido a `requirements.txt`; `ruff.toml` con solo exclusiones de código no activo (`legacy_reference/`, `venv/`, `.venv/`, `data/`, `logs/`, `notebooks/`)
- [x] Decisión tomada: conjunto de reglas por defecto de ruff (E4/E7/E9 + F), sin reglas de estilo adicionales por ahora — ver docs/decisions/0005-conjunto-de-reglas-de-ruff.md
- [x] Código formateado con `ruff format .` (29 archivos reformateados); confirmado con `pytest -v` que el formateo no cambió comportamiento (44/44 tests siguen pasando)
- [x] `.github/workflows/backend-ci.yml` — lint (`ruff check`) + formato (`ruff format --check`) + tests (`pytest -v`) en cada push/PR a `main`
