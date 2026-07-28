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

## Undo del swipe — capa de API (docs/ARCHITECTURE.md sección 11)

- [x] `rating_repository.delete(rating_id)` — `DELETE FROM ratings WHERE id = ?`, devuelve `True`/`False` según si borró una fila
- [x] `DELETE /domains/<domain_code>/ratings/<rating_id>?device_id=...` — mismo patrón de ownership que el `PATCH` ya existente (404 tanto si no existe como si es de otro `device_id`/dominio, para no revelar la existencia de un rating ajeno); responde `204` sin body
- [x] Tests de repository (`delete` existente devuelve `True` y la fila desaparece; `delete` inexistente devuelve `False`) y de integración vía `app.test_client()` (borrar un rating propio da `204` y desaparece de `pending-confirmation`; borrar el de otro `device_id` da `404`); caso también añadido al test parametrizado de "dominio inexistente da 404 en todas las rutas"
- [x] Suite completa: 63 tests, `pytest -v` en verde

**Diseñado en su momento (sección 11 de ARCHITECTURE.md) pero nunca implementado hasta ahora.** El consumo desde Flutter (botón/gesto de "volver atrás" en Descubrir) queda para un bloque de frontend futuro — este bloque es solo el endpoint.

## Testing (docs/ARCHITECTURE.md sección 5)

- [x] Infraestructura de pytest (`pytest.ini`, `tests/conftest.py`): fixture `temp_db` (BD SQLite aislada en `tmp_path`, valida el seed de `domains`/`signal_weights` en cada test) y `sample_items` (10 items sintéticos para el motor)
- [x] Tests del motor de recomendación (`tests/model/test_tfidf_engine.py`): señales positivas/negativas, fallback de peso cero, exclusión de items ya valorados, shrinkage con y sin preferencias explícitas, `top_n`, lista de ratings vacía
- [x] Contract tests de adapters (`tests/adapters/`, RAWG + TMDB, vía `requests_mock`): normalización de `community_score`, `TAG_DENYLIST`, `adapter_version`/`enrichment_version`, manejo de fallos de la API externa sin reventar
- [x] Tests de repositories (`tests/repositories/`, los 8 repos): incluye el hallazgo del `UNIQUE(user_id, item_id)` sin manejar en `rating_repository.create()`, resuelto con `ConflictError` + `get_by_user_and_item` en la capa de API
- [x] Tests de integración de API (`tests/integration/test_full_flow.py`) vía `app.test_client()` de Flask contra `temp_db`: flujo completo seed→ratings→job→resultado, 404 en las 4 rutas con `domain_code` inválido, idempotencia y conflicto de ratings duplicados, flujo de pending-confirmation, perfil y preferencias (incluido el reemplazo total, no fusión), job inexistente, y `X-Request-Id` presente en toda respuesta
- [x] Suite completa: 58 tests, `pytest -v` en verde

**Suite de testing completa.** Cubre motor, adapters, repositories y API de punta a punta.

## Frontend Flutter — fundamentos (docs/ARCHITECTURE.md secciones 4 y 7)

- [x] `frontend/anime_recommender_app/` renombrado a `frontend/swayp/` (`git mv`, conserva historial); `android/`, `ios/`, `web/`, `linux/`, `windows/`, `macos/` siguen ahí y compilaban
- [x] `pubspec.yaml`: `name: swayp`, descripción real del proyecto; dependencias nuevas añadidas con `flutter pub add` (versión estable más reciente resuelta por pub.dev, no inventada): `flutter_riverpod` 3.4.1, `dio` 5.11.0, `go_router` 17.3.0, `sqflite` 2.4.3, `uuid` 4.6.0, `flutter_local_notifications` 22.2.0 (requirió subir `http` de 0.13.6 a 1.6.0, sin uso real en el código todavía — `lib/` estaba vacío); `shared_preferences` sin tocar, ya estaba al día
- [x] `applicationId`/`namespace` de Android y `PRODUCT_BUNDLE_IDENTIFIER` de iOS actualizados a `com.sralex16.swayp` (antes `com.example.anime_recommender_app` / `com.example.animeRecommenderApp`; corregido de `com.srAlex16.swayp` a todo minúsculas, la mayúscula no sigue la convención de package names de Android). De paso, mismo id aplicado a macOS y nombres de binario/ventana en Linux y Windows (quedaban con el nombre viejo, se detectó al compilar para Linux)
- [x] `lib/main.dart` mínimo: `MaterialApp` envuelto en `ProviderScope` (Riverpod), `Scaffold` con el texto "Swayp" centrado — solo para validar que compila con el rebranding y las dependencias nuevas, sin arquitectura todavía (eso son los siguientes bloques)
- [x] `flutter pub get` y `flutter analyze` sin errores ni warnings
- [x] `flutter build linux --debug` compila y corre; `flutter test` pasa (smoke test a juego con el nuevo `main.dart`)
- [x] Plataforma Android regenerada con `flutter create --platforms=android --org com.sralex16 .` (herramienta oficial, no edición manual de versiones): sustituye los `build.gradle`/`settings.gradle` Groovy heredados (Gradle 7.5 / AGP 7.3.0 / Kotlin 1.7.10, incompatibles con el tooling de Flutter 3.44.7) por Kotlin DSL (`.kts`) con Gradle 9.1.0, ya compatibles. Requirió limpiar a mano el `gradle-wrapper.properties`/`.jar` viejo y el `gradle.properties` con flags inyectados por un intento de build fallido previo (ambos quedaban fuera del alcance de la regeneración porque estaban gitignored y `flutter create` no sobreescribe lo que ya existe en disco) antes de que la regeneración tomara efecto de verdad; también se eliminaron los `.gradle`/`MainActivity.kt` duplicados del `applicationId` antiguo que la regeneración dejó conviviendo junto a los nuevos. Un único ajuste manual necesario tras la regeneración: `core library desugaring` habilitado en `app/build.gradle.kts` (`isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`), requisito estándar y documentado de `flutter_local_notifications`, no relacionado con el desfase de Gradle
- [x] `flutter build apk --debug` compila (`✓ Built build/app/outputs/flutter-apk/app-debug.apk`); `flutter analyze` y `flutter test` repetidos tras la regeneración, ambos siguen en verde

**Fundamentos del frontend completados** (rebranding + dependencias + arranque mínimo confirmado, con build de Android real funcionando). Próximo bloque: arquitectura de carpetas (`core/`, `domain/`, `data/`, `features/`) siguiendo docs/ARCHITECTURE.md sección 4.2.

## Nuevas ideas
- [x] Botón de rollback en la pantalla principal. En caso de que el usuario se equivoque, que pueda modificar la última opción
- [x] Blocklist. En Tinder hay un sistema para coger a los contactos directamente desde la agenda del teléfono y bloquearlos para que no aparezcan en la pantalla principal. En Swayp hay que hacer algo parecido, es decir, que el usuario pueda añadir obras que conoce y ha consumido (independientemente de si les gusta o no (aunque realmente estaría bien saber si esas obras les ha gustado para entrenar al modelo)) para que estas no aparezcan en la pantalla principal
- [x] Entrenar el modelo en función del gusto del usuario. Con forme va dando likes / dislikes, vectorizar ese registro para ir recomendando obras cada vez más similares o que puedan gustale. Es decir, cuando tengamos el algoritmo entrenado, podríamos saltarnos esta regla aleatóriamente cada X recomendaciones, de forma que salga una recomendación diferente a las vectorizadas para tener obras variadas dentro del algoritmo y no recomendar siempre lo mismo
- [x] Modo oscuro. El usuario puede elegir manualmente o de forma automáticacogiendo el modo por defecto del dispositivo
- [x] Cambiar idioma. El usuario puede elegir entre español o inglés o que se ponga solo en función del idioma del dispositivo
- [x] Filtros para mostrar obras. Género, edad recomendada, duración estimada...
- [x] pantalla de guardado no se actualiza automáticamente. Cuando doy like, no aparece nada, para que aparezcan las obras hay que refrescar la pantalla cerrando la app y volviendola a abrir
