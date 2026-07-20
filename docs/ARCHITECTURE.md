# Arquitectura — Recomendador Multi-Dominio

Documento de diseño previo a implementación. Cubre backend, frontend, modelo de datos, contrato de API, logging/trazabilidad, testing y CI/CD.

---

## 1. Objetivos de diseño

- **Un solo motor de recomendación**, agnóstico de dominio (películas, libros, videojuegos, board games...).
- **Añadir un dominio nuevo = escribir un adaptador**, sin tocar el motor ni la mayoría de la UI.
- **Sin dependencia de perfiles externos públicos** (nada de "tu lista de MAL debe ser pública"): el perfil nace dentro de la app vía onboarding.
- **Trazabilidad de extremo a extremo**: poder seguir una recomendación concreta desde el tap del usuario en Flutter hasta la fila de la base de datos que la generó.
- **Nada de lógica de negocio bloqueante en el hilo de la request** (el pipeline ML puede tardar; se gestiona como job asíncrono).

---

## 2. Diagrama de alto nivel

```
┌─────────────────────┐        HTTPS/JSON        ┌──────────────────────────┐
│   Flutter App        │ ────────────────────────▶│   Backend API (Flask)    │
│  (Android/iOS/Web)    │◀──────────────────────── │                          │
└─────────────────────┘                           │  ┌────────────────────┐  │
                                                    │  │  API / Controllers │  │
                                                    │  └─────────┬──────────┘  │
                                                    │            ▼             │
                                                    │  ┌────────────────────┐  │
                                                    │  │   Service Layer     │  │
                                                    │  └─────────┬──────────┘  │
                                                    │            ▼             │
                                        ┌───────────┼──┬───────────────────┐  │
                                        │           │  │                   │  │
                              ┌─────────▼──┐  ┌──────▼──────┐   ┌──────────▼┐ │
                              │  ML Core    │  │ Repositories │   │ Adapters  │ │
                              │ (TF-IDF/SVD)│  │  (SQLite)    │   │ (por      │ │
                              │  agnóstico  │  │              │   │ dominio)  │ │
                              └─────────────┘  └─────────────┘   └─────┬─────┘ │
                                                    └──────────────────┼───────┘
                                                                        ▼
                                                         ┌───────────────────────┐
                                                         │  APIs externas         │
                                                         │  TMDB / RAWG /         │
                                                         │  Open Library / BGG    │
                                                         └───────────────────────┘
```

---

## 3. Backend

### 3.1 Capas

| Capa | Responsabilidad | No debe hacer |
|---|---|---|
| **API / Controllers** | Recibir request, validar input, llamar al service, formatear response | Lógica de negocio, acceso directo a BD |
| **Service** | Orquestar el caso de uso (ej. "generar recomendaciones") | Saber de HTTP ni de SQL |
| **ML Core** | Implementa la interfaz `RecommendationEngine` (`score(item, user_profile) -> float`) sobre `Item` genérico. Primera implementación: `TFIDFRecommendationEngine` (TF-IDF + SVD + scoring híbrido). Cambiar de algoritmo (ej. embeddings con Sentence Transformers) en el futuro es sustituir la implementación, no tocar servicios ni controllers | Saber qué dominio es, ni de dónde vino el dato |
| **Adapters** (por dominio) | Llamar a la API externa, **normalizar** su respuesta a `Item`, **enriquecer** (construir un campo de texto canónico para el motor combinando sinopsis/keywords/géneros según lo que aporte cada fuente, con longitud acotada — ver nota más abajo) y normalizar `community_score` a escala 0-1 (TMDB, RAWG y BGG usan escalas distintas; toda esta conversión ocurre aquí, no en el ML Core, para que este siga sin saber nada de dominios) | Guardar en BD, ni saber de recomendación |
| **Repositories** | Acceso a BD (CRUD de users/items/ratings/blacklist/jobs) | Lógica de negocio |
| **Cross-cutting** | Logging, config, manejo de errores, jobs asíncronos | — |

Regla simple: cada capa solo conoce la de justo debajo. El controller nunca importa un adapter directamente, el ML Core nunca importa Flask.

**Nota sobre el enriquecimiento**: TMDB da sinopsis largas y `keywords`; RAWG da géneros/plataformas con poco texto libre; OpenLibrary da `subjects` a veces muy pobres; BGG tiene mecánicas y categorías propias. Sin normalizar cuánto "texto" entra al TF-IDF por ítem, el dominio con fuente más rica sesga la calidad de sus propias recomendaciones frente a los demás — no es que un dominio "recomiende mejor" en sí, es que su fuente de datos es mejor. Cada adapter construye un campo `text_for_vectorization` con una plantilla consistente (ej. `título + top-N tags/géneros + sinopsis truncada a M caracteres`), así el TF-IDF recibe una cantidad de señal comparable venga de donde venga el ítem.

### 3.2 Estructura de carpetas propuesta

```
src/
  api/
    routes/
      domains.py
      recommendations.py
      ratings.py
      blacklist.py
      jobs.py
    schemas/            # (de)serialización + validación de requests/responses
  services/
    recommendation_service.py
    onboarding_service.py
    blacklist_service.py
    job_service.py
  adapters/
    base_adapter.py     # interfaz común (fetch_seed, fetch_by_id, search)
    tmdb_adapter.py
    rawg_adapter.py
    openlibrary_adapter.py
    bgg_adapter.py
  model/
    item.py             # dataclass/pydantic: Item genérico
    engine.py           # interfaz RecommendationEngine (score, fit/rebuild)
    tfidf_engine.py      # TFIDFRecommendationEngine, primera implementación
    hybrid_scorer.py
  repositories/
    user_repository.py
    item_repository.py
    rating_repository.py
    blacklist_repository.py
    job_repository.py
  core/
    logging_config.py
    errors.py
    config.py
    db.py
tests/
  unit/
  integration/
  contract/             # verifican que cada adapter normaliza bien a Item
```

### 3.3 Modelo de datos (SQLite)

```sql
-- Un dominio = "movies", "books", "games", "boardgames"
CREATE TABLE domains (
  code TEXT PRIMARY KEY,        -- 'movies'
  display_name TEXT NOT NULL,   -- 'Películas'
  adapter_name TEXT NOT NULL,   -- 'tmdb_adapter'
  enabled BOOLEAN DEFAULT 1
);

CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  device_id TEXT UNIQUE NOT NULL,  -- no hace falta login real, un id local basta
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Caché normalizado de ítems externos (evita golpear TMDB/RAWG en cada request)
CREATE TABLE items (
  id INTEGER PRIMARY KEY,
  domain_code TEXT NOT NULL REFERENCES domains(code),
  external_id TEXT NOT NULL,       -- id en la API origen
  title TEXT NOT NULL,
  description TEXT,
  text_for_vectorization TEXT,     -- campo canónico construido por el adapter (ver 3.1), lo que realmente entra al TF-IDF
  tags TEXT,                       -- JSON array serializado (uso genérico/display)
  community_score REAL,
  image_url TEXT,                  -- imagen principal, para listados/miniaturas
  external_url TEXT,
  adapter_version TEXT NOT NULL,   -- qué versión del adapter generó este registro
  fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(domain_code, external_id)
);

-- Carrusel de imágenes de la tarjeta (además de la imagen principal de arriba)
CREATE TABLE item_images (
  item_id INTEGER NOT NULL REFERENCES items(id),
  url TEXT NOT NULL,
  position INTEGER NOT NULL,       -- orden dentro del carrusel
  PRIMARY KEY (item_id, position)
);

-- Pesos de cada tipo de señal para el scoring híbrido (sección 9), editables
-- sin migrar nada
CREATE TABLE signal_weights (
  status TEXT PRIMARY KEY,         -- 'rejected' | 'interested' | 'known_liked' | 'known_disliked'
  weight REAL NOT NULL
);
-- seed inicial: rejected=-1.0, interested=0.3, known_liked=1.0, known_disliked=-1.0

CREATE TABLE ratings (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  item_id INTEGER NOT NULL REFERENCES items(id),
  domain_code TEXT NOT NULL REFERENCES domains(code),
  status TEXT NOT NULL,            -- 'rejected' | 'interested' | 'known_liked' | 'known_disliked'
  source TEXT NOT NULL,            -- 'onboarding' | 'feedback' | 'saved_confirmation'
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- se actualiza al confirmar desde Guardados
  UNIQUE(user_id, item_id)
);

CREATE TABLE blacklist (
  user_id INTEGER NOT NULL REFERENCES users(id),
  item_id INTEGER NOT NULL REFERENCES items(id),
  domain_code TEXT NOT NULL REFERENCES domains(code),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, item_id)
);
-- Distinto de ratings.status='rejected': 'rejected' es señal de entrenamiento
-- (swipe izquierda, el ítem en teoría podría reaparecer si el contexto cambia
-- mucho); blacklist es exclusión dura y permanente, acción explícita desde la
-- tarjeta expandida ("no me interesa esto, no me lo enseñes nunca más").

-- Trabajos asíncronos (generación de recomendaciones, refresco de catálogo)
CREATE TABLE jobs (
  id TEXT PRIMARY KEY,             -- uuid
  type TEXT NOT NULL,              -- 'generate_recommendations' | 'refresh_catalog'
  user_id INTEGER REFERENCES users(id),
  domain_code TEXT REFERENCES domains(code),
  status TEXT NOT NULL,            -- 'pending' | 'running' | 'done' | 'error'
  engine_version TEXT,             -- qué implementación de RecommendationEngine generó el resultado (ej. 'tfidf-1.0')
  result TEXT,                     -- JSON con el resultado si status='done'
  error_message TEXT,
  request_id TEXT NOT NULL,        -- para trazabilidad (ver sección 3.6)
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

Ambos versionados (`adapter_version` en `items`, `engine_version` en `jobs`) son baratos de añadir y encajan directamente con lo que ya nos importaba de trazabilidad (sección 3.6): permiten responder "¿con qué versión del algoritmo/adapter se generó esta recomendación concreta?" sin tener que reconstruirlo de memoria.

```sql
-- Esquema de filtros/facetas por dominio (config-driven: la UI de filtros se
-- genera dinámicamente a partir de esto, así que añadir/quitar un filtro es
-- un cambio de datos, no de código Flutter)
CREATE TABLE domain_facets (
  id INTEGER PRIMARY KEY,
  domain_code TEXT NOT NULL REFERENCES domains(code),
  facet_key TEXT NOT NULL,        -- 'genre', 'subtype', 'age_rating'...
  label TEXT NOT NULL,            -- 'Género' (texto a mostrar en el menú)
  scope TEXT NOT NULL,            -- 'global' | 'domain_specific'
  input_type TEXT NOT NULL,       -- 'single_select' | 'multi_select' | 'range'
  allowed_values TEXT,            -- JSON array, si aplica
  UNIQUE(domain_code, facet_key)
);

-- Valores de cada faceta por ítem (sustituye a un campo "tags" plano;
-- permite que un ítem tenga varios valores en la misma faceta, ej. varios géneros)
CREATE TABLE item_attributes (
  item_id INTEGER NOT NULL REFERENCES items(id),
  facet_key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (item_id, facet_key, value)
);

-- Selección de filtros del usuario, persistida por dominio (para que no se
-- pierda al salir y volver a entrar en ese dominio)
CREATE TABLE user_domain_filters (
  user_id INTEGER NOT NULL REFERENCES users(id),
  domain_code TEXT NOT NULL REFERENCES domains(code),
  facet_key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (user_id, domain_code, facet_key, value)
);

-- Perfil de usuario (ver sección 9 sobre cómo se usa cada campo)
CREATE TABLE user_profile (
  user_id INTEGER PRIMARY KEY REFERENCES users(id),
  age INTEGER,                    -- filtro duro de clasificación por edad
  gender TEXT,                    -- opcional; ver sección 9, no se usa para ponderar gustos por defecto
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Gustos declarados explícitamente por el usuario en el perfil, por dominio
-- (distinto de las ratings implícitas que salen del swipe)
CREATE TABLE user_explicit_preferences (
  user_id INTEGER NOT NULL REFERENCES users(id),
  domain_code TEXT NOT NULL REFERENCES domains(code),
  facet_key TEXT NOT NULL,        -- normalmente 'genre'
  value TEXT NOT NULL,
  weight REAL DEFAULT 1.0,
  PRIMARY KEY (user_id, domain_code, facet_key, value)
);
```

Notas:
- `items` actúa como caché: los adapters solo se llaman cuando hace falta refrescar el catálogo de un dominio (job programado o manual), no en cada petición de recomendación.
- `ratings.status` + `signal_weights` sustituye a un simple score -1/+1: permite distinguir interés (aceptar sin conocer) de gusto confirmado (aceptar conociendo, o confirmado luego desde Guardados) sin cambiar el esquema si se afinan los pesos — ver sección 9 y sección 7.3.
- `ratings` es también el registro de swipes: cada swipe derecha/izquierda es un insert aquí. El botón "volver atrás" hace un `DELETE` de la última fila (ver sección 10).

### 3.4 Contrato de la API

Prefijo de versión desde el día 1 (`/api/v1/...`) para poder evolucionar sin romper clientes viejos.

```
GET  /api/v1/domains
     → [{code, display_name, enabled}]

GET  /api/v1/domains/{domain}/seed?user_id=X&count=20
     → ítems para onboarding (excluye ya puntuados)

POST /api/v1/domains/{domain}/ratings
     body: {user_id, item_id, status}   # status: 'rejected' | 'interested' | 'known_liked' | 'known_disliked'
     → 201 { rating }

POST /api/v1/domains/{domain}/recommendations/jobs
     body: {user_id}
     → 202 { job_id }              # nunca bloqueante

GET  /api/v1/jobs/{job_id}
     → { status, result? , error_message? }

GET/POST/DELETE /api/v1/domains/{domain}/blacklist

GET  /api/v1/domains/{domain}/filters
     → esquema de facetas para renderizar el menú de filtros dinámicamente
     [{facet_key, label, scope, input_type, allowed_values}]

PUT  /api/v1/users/{user_id}/domains/{domain}/filters
     body: {filters: [{facet_key, values: [...]}]}
     → guarda la selección de filtros del usuario para ese dominio

GET/PUT /api/v1/users/{user_id}/profile
     body: {age, gender?}

GET/PUT /api/v1/users/{user_id}/domains/{domain}/preferences
     body: [{facet_key, value, weight}]
     → gustos declarados explícitamente en el perfil (ver sección 9)

DELETE /api/v1/ratings/{rating_id}
     → deshacer un swipe (botón "volver atrás", ver sección 10)
```

**Formato de error estandarizado** (igual en todos los endpoints):
```json
{
  "error": {
    "code": "EXTERNAL_API_TIMEOUT",
    "message": "TMDB no respondió a tiempo",
    "request_id": "a1b2c3d4"
  }
}
```

Jerarquía de excepciones propia (`core/errors.py`): `AppError` → `ExternalApiError`, `NotFoundError`, `ValidationError`, `JobFailedError`. Cada una mapea a un código HTTP y un `error.code` fijo, para que Flutter pueda decidir la UI según el código, no parseando el mensaje.

### 3.5 Jobs asíncronos (resuelve el timeout de 5 minutos actual)

Flujo:
1. Flutter hace `POST /recommendations/jobs` → recibe `job_id` al instante (202 Accepted).
2. Backend encola el trabajo (para el alcance del curso, un hilo/proceso en background es suficiente; no hace falta Celery/Redis).
3. Flutter hace polling a `GET /jobs/{job_id}` cada 2-3s, o mejor, usas Server-Sent Events si quieres reutilizar el patrón que ya conoces de Sity.
4. Cuando `status = done`, el `result` trae las recomendaciones.

Esto también evita que una request HTTP colgada 5 minutos tumbe el worker de Render en el plan gratuito — que es exactamente lo que hace hoy `app.py` al lanzar `get_recommendations_for_user.py` como subproceso síncrono con `timeout=300`.

**Refresco de catálogo** (`type='refresh_catalog'`): job independiente, uno por dominio, disparado por cron (ej. GitHub Actions con `schedule`, o un cron job de Render) con periodicidad razonable (diaria o semanal, según cuota de la API externa), más un disparo manual disponible para forzarlo antes de una demo o entrega.

### 3.6 Logging y trazabilidad

- **`request_id`** generado en el middleware de entrada (o recibido si el cliente ya lo manda) y propagado por todas las capas vía contexto (no como parámetro explícito en cada función — usar `contextvars` en Python).
- Flutter genera su propio `request_id` (uuid) por cada acción de usuario relevante y lo manda en un header (`X-Request-Id`); si hay un `job_id` asociado, ambos quedan enlazados en el log y en la tabla `jobs`. Así puedes seguir "el usuario tocó el botón → esta request → este job → estas filas de rating consultadas → este resultado".
- Logs en **formato JSON estructurado** (no strings tipo `print('❌ Error...')` como hoy), un log por línea, campos mínimos: `timestamp, level, request_id, layer, event, message, extra`.
- Niveles: `DEBUG` (detalle interno, ej. qué ítems entraron en el TF-IDF), `INFO` (eventos de negocio: "recomendación generada, 12 ítems"), `WARNING` (fallback usado, caché expirada), `ERROR` (excepción capturada).
- El ML Core debería loguear en `DEBUG` el desglose del score híbrido (similitud vs. score de comunidad) por cada ítem recomendado — no solo para depurar, sino porque es material perfecto para la memoria del curso ("así explico por qué recomendó esto").

### 3.7 Configuración y secretos

- `.env` (no versionado) + `.env.example` (sí versionado, con claves vacías) para `TMDB_API_KEY`, `RAWG_API_KEY`, `DATABASE_URL`, etc.
- `core/config.py` centraliza la carga (pydantic `BaseSettings` o similar), nada de `os.environ.get()` disperso por el código.

---

## 4. Frontend (Flutter)

### 4.1 Capas

| Capa | Contenido |
|---|---|
| **Presentation** | Screens y widgets, sin lógica de negocio |
| **State (Riverpod)** | Providers/Notifiers que orquestan casos de uso y exponen estado a la UI |
| **Domain** | Modelos (`Item`, `Domain`, `Rating`) y casos de uso (`GetRecommendationsUseCase`, `SubmitRatingUseCase`) |
| **Data** | `ApiClient` (dio), repositorios que implementan las interfaces del dominio, caché local |
| **Core** | Theming, routing (`go_router`), logging de cliente, manejo global de errores |

### 4.2 Estructura de carpetas propuesta

```
lib/
  core/
    logging/app_logger.dart
    routing/app_router.dart
    theme/
    errors/app_exception.dart
  domain/
    models/item.dart
    models/domain.dart
    usecases/get_recommendations_usecase.dart
    usecases/submit_rating_usecase.dart
  data/
    api/api_client.dart          # dio + interceptor de logging + request_id
    repositories/recommendation_repository_impl.dart
    repositories/rating_repository_impl.dart
  features/
    domain_selection/
      domain_selection_screen.dart
      domain_selection_provider.dart
    onboarding/
      onboarding_screen.dart      # genérica, parametrizada por domain
      onboarding_provider.dart
    recommendations/
      recommendations_screen.dart # genérica, parametrizada por domain
      recommendations_provider.dart
    blacklist/
      blacklist_overlay.dart
      blacklist_provider.dart
```

Punto clave: **una sola pantalla de onboarding y una sola de recomendaciones**, ambas reciben `domain` como parámetro (vía `go_router` o el provider), no una por cada dominio.

### 4.3 Estado y flujo de dominio seleccionado

- Un `selectedDomainProvider` (Riverpod `StateProvider`) guarda el dominio activo.
- Los providers de onboarding/recomendaciones/blacklist son `family` providers parametrizados por `domain`, así Riverpod cachea el estado de cada dominio por separado sin que se pisen entre sí (importante porque el usuario puede ir y volver entre Películas y Libros sin perder progreso).

### 4.4 Logging en cliente

- `dio` con un interceptor que loguea cada request/response (método, URL, status, duración) y genera el `X-Request-Id`.
- En builds de release, estos logs no deberían ir a consola sino a un sink descartable o a un servicio si en el futuro se añade (Sentry, etc.) — para el curso, consola estructurada es suficiente, pero conviene dejar el punto de extensión ya montado.

### 4.5 Manejo de errores y estados de UI

Cada pantalla modela su estado como algo tipo:
```dart
sealed class ScreenState<T> {}
class Loading<T> extends ScreenState<T> {}
class Success<T> extends ScreenState<T> { final T data; }
class Failure<T> extends ScreenState<T> { final AppException error; }
```
Y el `error.code` que viene del backend (sección 3.4) decide el mensaje/acción en UI (ej. `EXTERNAL_API_TIMEOUT` → "inténtalo de nuevo en un momento" con botón de retry; `NOT_FOUND` → mensaje distinto). Nada de mostrar el `Exception.toString()` crudo como hace la app actual.

---

## 5. Testing

### 5.1 Backend
- **Unit**: ML Core con datos sintéticos (verificar que el scoring híbrido pondera bien similitud vs. score comunidad), repositories contra SQLite en memoria.
- **Contract tests de adapters**: por cada adapter, un test que mockea la respuesta cruda de la API externa (fixture JSON guardada) y verifica que el `Item` normalizado tiene todos los campos obligatorios rellenos. Esto es lo que te avisa si TMDB cambia su esquema de respuesta.
- **Integration**: flujo completo `POST rating → POST job → GET job` contra una BD de test.

### 5.2 Frontend
- **Widget tests** de `onboarding_screen` y `recommendations_screen` con un repositorio fake (sin red real).
- **Provider tests** de Riverpod (`ProviderContainer` en tests) para la lógica de estado, separado de la UI.

---

## 6. CI/CD

### 6.1 Ramas
- `main` (protegida, deploy automático), `develop` (integración), `feature/*` (una por tarea). PRs a `develop` requieren CI en verde.

### 6.2 Pipeline backend (GitHub Actions)
```
on: pull_request → main/develop
jobs:
  lint:    ruff/flake8 + black --check
  test:    pytest (unit + integration + contract)
  build:   docker build (si se dockeriza) o simplemente valida requirements.txt
deploy (solo en push a main):
  Render ya soporta auto-deploy on push; el job de CI en main solo necesita
  pasar test antes de que Render despliegue (o usar Render "Deploy Hook"
  disparado manualmente al final del job si quieres control explícito).
```

### 6.3 Pipeline frontend (GitHub Actions)
```
on: pull_request → main/develop
jobs:
  analyze: flutter analyze
  test:    flutter test --coverage
  build:   flutter build apk --release (artifact subido a la Action,
           descargable para la entrega del curso sin depender de un store)
```

---

## 7. Pantallas y UX (estilo swipe)

**Navegación**: barra inferior de 3 pestañas — **Descubrir** (swipe), **Guardados**, **Perfil**. El filtro ya no es un menú hamburguesa (eso implicaría navegación, y la navegación ya la resuelve la barra inferior); es un icono de filtro dentro de Descubrir que abre un panel/bottom sheet.

### 7.1 Pantalla de recomendaciones (swipe)

Es la pantalla principal, y hace doble función: onboarding (primera vez en un dominio, baraja semilla) y recomendación continua (baraja generada por el motor). Mismo widget, mismo flujo de datos, distinto origen de la baraja.

**Componentes:**
- Card stack en primer plano con gestos de swipe. **Contenido en primer plano** (visible sin tocar nada): carrusel de imágenes (`item_images`) a pantalla casi completa, y overlay inferior con título, año y 1-2 badges (género principal, subtipo si aplica) — lo mínimo para decidir en un vistazo. **Contenido expandible** (tap en la carta, no swipe): sinopsis completa, todos los géneros/tags, score de comunidad. El tap queda libre para quien quiere más info antes de decidir, sin interferir con el gesto de swipe.
- Toggle discreto **"Ya lo conozco"** en la propia tarjeta: si el usuario lo activa antes de decidir, el swipe deja de significar "interés" y pasa a pedir una respuesta directa de gusto (me gustó / no me gustó) en vez de "quiero verlo". Resuelve con fricción mínima el caso de que aparezca algo que el usuario ya ha consumido (sección 7.3 lo trata en detalle).
- Botones espejo de los gestos (rechazar / aceptar / volver atrás) — no solo por accesibilidad, también porque si en algún momento la app corre en web/desktop (útil para la entrega del curso), el gesto de swipe no siempre está disponible.
- Icono de filtro → panel de filtros, generado dinámicamente a partir de `GET /domains/{domain}/filters` (sección 8).

**Flujo de datos (importante para que el swipe se sienta instantáneo):**
1. Al entrar, se pre-carga un lote de N ítems (ej. 10) vía el job de recomendaciones. **Baraja semilla (primera vez en un dominio)**: no debe ser aleatoria pura ni "los más populares" sin más — conviene una muestra estratificada por género/subtipo, para cubrir el espacio de gustos del usuario en pocos swipes y no sesgar el arranque hacia un solo género por casualidad del muestreo.
2. Cada swipe es **optimista**: se actualiza la UI al instante y el rating se encola localmente (una cola simple en el dispositivo, ej. con `sqflite`/`Hive`), no se espera la respuesta del servidor antes de mostrar la siguiente carta.
3. Un worker en background vacía la cola contra `POST /domains/{domain}/ratings`, con reintento si falla la red.
4. Cuando quedan pocas cartas en el lote local (ej. 3), se pide el siguiente lote por adelantado.

**Estados vacíos**: la pantalla debe distinguir explícitamente entre (a) *generando* (el job aún no ha devuelto el primer lote — spinner con mensaje, no pantalla en blanco), (b) *sin resultados por los filtros activos* (mensaje + acceso directo al panel de filtros para relajarlos), y (c) *catálogo agotado* (el usuario ha visto todo lo disponible en ese dominio con esos filtros — mensaje + sugerencia de esperar al próximo refresco de catálogo o probar otro dominio). Son tres pantallas de vacío distintas, no un único "no hay más".

Esto también hace la app tolerante a conexión intermitente, algo nada trivial si la entrega se hace en un entorno con wifi de aula poco fiable.

### 7.2 Pantalla de perfil

- Edad, sexo (opcional), y gustos declarados explícitamente por dominio (chips de género u otras facetas marcadas como "preferencia", no solo filtro).
- Importante: aquí el usuario declara *lo que dice que le gusta*; el swipe genera *lo que demuestra con su comportamiento*. Son señales distintas y se combinan con pesos distintos (sección 9).

### 7.3 Pantalla de Guardados

Lista de ítems con `status = 'interested'` (aceptados sin marcar "ya lo conozco"). Cada tarjeta de esta lista tiene la pregunta de confirmación ("¿ya lo has visto/jugado?" → si sí, "¿te gustó?"), que al responderse actualiza el `status` a `known_liked`/`known_disliked` y dispara el reentreno de esa señal. No hace falta responder todas de golpe; es una lista viva que se va vaciando con el tiempo.

---

## 8. Taxonomía de filtros: generales vs. específicos

**Filtros globales** (aplican a cualquier dominio, viven como columnas fijas o facetas con `scope='global'`): edad recomendada, año de publicación, umbral de score de comunidad.

**Filtros específicos de dominio** (`scope='domain_specific'`, definidos en `domain_facets`): p. ej. en "Audiovisual" → subtipo (película/serie/anime) y género; en "Libros" → género y longitud; en "Videojuegos" → plataforma y género.

**La regla para decidir si algo es un dominio nuevo o un subtipo/género dentro de uno existente:**

> ¿La señal de recomendación —de qué API viene el dato, qué forma tienen sus metadatos, y qué comparten los ítems dentro de la misma baraja— es estructuralmente la misma que la de sus vecinos en ese dominio?
> - **Sí** → es un subtipo o un valor de género dentro del dominio existente.
> - **No** (fuente de datos distinta, forma de metadatos distinta, patrón de consumo distinto) → merece dominio propio.

Aplicando la regla a tus dos ejemplos:
- **Anime** → mismos metadatos que cine/series (sinopsis, género, póster, misma clase de fuente) → subtipo dentro de "Audiovisual", con la faceta `genre` pudiendo incluir valores propios de anime si hace falta (ej. "isekai", "shonen") sin que eso rompa nada del modelo.
- **Podcast** → metadatos episódicos, sin taxonomía de género real tipo música, fuente de datos distinta, patrón de consumo distinto → si algún día se añade, dominio propio, no subtipo de música (y recuerda que descartamos música como dominio porque Spotify ya lo hace mejor — el mismo argumento aplicaría a podcasts si Spotify también los recomienda bien).

Esta regla no resuelve todos los casos futuros de un plumazo, pero te da un criterio consistente para cuando aparezca el siguiente caso raro, en vez de decidir cada vez de forma ad-hoc.

---

## 9. Modelo de perfil y ponderación

Puntuación de un ítem candidato:

```
score(item) = w_implicit · similitud_implicita(item, usuario)
            + w_explicit · coincidencia_preferencias_declaradas(item, usuario)
            + w_community · score_comunidad_normalizado(item)
```

- **`similitud_implicita`**: similitud coseno entre el vector TF-IDF del ítem y el vector de preferencia del usuario, construido a partir de sus `ratings` ponderados por `signal_weights` según su `status` (`rejected`/`interested`/`known_liked`/`known_disliked` — sección 7.1 y 8.3), y ponderando además más los swipes recientes que los antiguos (para que el gusto pueda "derivar" con el tiempo). **Shrinkage con pocos datos**: con menos de un mínimo de señales fuertes (ej. 5 `known_liked`/`known_disliked`), el vector implícito se atenúa hacia un vector neutro/general en vez de tomarse al pie de la letra — así 5 swipes casuales de RPG no hacen que el sistema asuma "100% RPG" solo porque fueron las primeras cartas que tocaron.
- **`coincidencia_preferencias_declaradas`**: si los valores de faceta del ítem intersectan con lo que el usuario marcó explícitamente en su perfil, pondera según el `weight` que puso. Estas preferencias declaradas, si se piden ya en el primer uso del dominio (no solo en ajustes de perfil), también sirven para **excluir géneros de la propia baraja semilla** — si el usuario dice que no le interesa el terror, ni siquiera se lo enseñes en el onboarding.
- **Arranque en frío**: `w_explicit` empieza alto y `w_implicit` bajo cuando el usuario tiene pocos swipes en ese dominio; a medida que acumula swipes, los pesos se invierten (una función simple tipo `w_explicit = max(0.1, 1 - swipes/50)` es suficiente para el alcance del curso, no hace falta nada más sofisticado).
- **`w_community` tiene techo fijo, nunca domina**: sin límite, un ítem con score de comunidad 9.4 siempre gana a uno con 7.1 aunque encaje peor con el usuario, y el sistema degenera en "recomendar siempre lo popular" — justo lo contrario de personalizar. Techo recomendado: `w_community` entre 0.10 y 0.20 del total, el resto repartido entre implícito y explícito.
- **Edad**: se trata como **filtro duro**, no como parte de la puntuación — un ítem fuera del rango de edad ni siquiera entra en el conjunto de candidatos, no se le resta puntuación.
- **Sexo**: aquí te doy una recomendación de diseño, no solo técnica. Yo **no lo usaría como señal de ponderación de gustos** por defecto. Dos razones, una técnica y una de fondo: (1) correlacionar sexo con género de contenido reproduce estereotipos estadísticos de la población en vez de reflejar el gusto real de esa persona concreta — y el swipe ya te da una señal de comportamiento mucho más fiable que cualquier proxy demográfico; (2) es el típico caso de "el sistema decide que a ella le gusta el romance y a él la acción" que además de ser menos preciso, es el tipo de sesgo que conviene evitar si puedes. Si quieres guardar el campo por otros motivos (estadísticas de uso, clasificación de contenido en algunas plataformas), guárdalo, pero no lo metas en la fórmula de scoring.
- **Explicabilidad visible al usuario**: el desglose del score ya se loguea en `DEBUG` (sección 3.6) para la memoria del curso; como ese cálculo ya existe, casi no cuesta nada exponer su resumen en la tarjeta expandida ("te lo recomendamos porque: coincide con fantasía · similar a algo que te gustó · buena valoración de la comunidad"). Aporta producto (confianza del usuario) y memoria (demuestra que el sistema razona, no solo puntúa) al mismo coste de cálculo.

---

## 10. "Volver atrás" (undo)

Alcance para v1: **undo de un solo nivel** (como Tinder — no hay historial de deshacer múltiple). Es una limitación de alcance deliberada, no una limitación de arquitectura: se puede ampliar después sin rediseñar nada.

Comportamiento:
1. Si el último swipe **todavía está en la cola local sin sincronizar** (sección 7.1): el undo simplemente cancela ese envío pendiente y reinserta la carta al principio de la baraja local. Cero llamadas a red.
2. Si el último swipe **ya se sincronizó** con el backend: el cliente llama a `DELETE /ratings/{rating_id}` (el `rating_id` se guarda localmente tras cada sync exitoso) y reinserta la carta.

En ambos casos la UI se comporta igual para el usuario; la diferencia de sincronizado/no-sincronizado es invisible, solo importa a nivel de implementación.

---

## 11. Notificaciones y retención

**Principio de diseño**: retener al usuario a base de valor real (mejores recomendaciones, transparencia de por qué se recomienda algo, cierre útil del bucle de confirmación), no de patrones manipulativos (rachas con culpa, urgencia falsa, refuerzo variable). Además de ser mejor diseño, es más fácil de justificar en la memoria del curso.

**Tipos de notificación:**

| Tipo | Trigger | Objetivo |
|---|---|---|
| Recordatorio de confirmación | X días desde que un ítem entró en Guardados sin confirmar, o al acumularse N pendientes | Cerrar el bucle que alimenta al modelo (la más valiosa de las tres) |
| Reactivación | Inactividad de varios días (ej. 5-7 — nunca diario) | Traer de vuelta sin presionar |
| Resumen semanal (opcional) | Cada X días con actividad reciente | Mostrar qué ha aprendido el modelo sobre sus gustos (reutiliza el logging del score híbrido, sección 3.6) |

**Decisión técnica**: v1 completamente local, sin backend. Los tres triggers se calculan con datos que ya viven en el dispositivo (última apertura de la app, conteo de pendientes en Guardados), así que `flutter_local_notifications` con notificaciones programadas es suficiente — no hace falta Firebase Cloud Messaging todavía. Push real (FCM) quedaría como ampliación de v2, solo si en algún momento se quiere que el *backend* dispare una notificación (ej. "el catálogo se ha refrescado con algo que encaja mucho contigo"), lo cual añade infraestructura (tokens de dispositivo, claves de Firebase) que no compensa para el alcance actual.

**Módulo Flutter** (capa `core/`, coherente con la separación de capas ya definida):
```
lib/core/notifications/
  notification_service.dart     # wrapper de flutter_local_notifications
  notification_triggers.dart    # lógica de cuándo programar cada tipo
  notification_preferences.dart # on/off por tipo, guardado en local storage
```

- Preferencias por tipo (el usuario puede desactivar cada categoría por separado) guardadas localmente (`shared_preferences`), sin necesidad de tabla en el backend mientras no haya push.
- Log local simple de notificaciones mostradas/abiertas (una tabla sqlite en el propio dispositivo), útil tanto para no repetir la misma notificación de más, como para tener datos de "efectividad" que mostrar en la memoria del curso.
- Flujo de permiso de notificaciones gestionado explícitamente (Android 13+ e iOS lo piden en runtime, no basta con declararlo en el manifest) — pedirlo en un momento con contexto (ej. justo después del primer ítem guardado sin confirmar), no nada más abrir la app por primera vez.

---

## 12. Decisiones de alcance explícitas

Para que quede claro qué es limitación deliberada y qué es simplemente "todavía no":

- **Identidad por `device_id`, sin login real**: sin cuentas, sin sync entre dispositivos. Razonable para un proyecto de curso; si se pierde la app se pierde el perfil. Ampliable a login real más adelante sin rediseñar el resto (solo cambiaría cómo se resuelve `user_id`).
- **Notificaciones v1 sin push/FCM**: solo locales (sección 11). Push queda como ampliación de v2 si se necesita que el backend dispare notificaciones.
- **Sin colaborativo, solo contenido**: el motor recomienda por similitud de contenido + comportamiento propio del usuario, no compara usuarios entre sí ("a gente parecida a ti también le gustó..."). Es una ampliación futura razonable, pero añade complejidad (necesitarías suficientes usuarios reales) que no aporta en la fase de curso.
- **Sin multi-idioma en el diseño base**: la app anterior tenía ES/EN. No lo incluyo como requisito del rediseño; si sobra tiempo al final es una capa que se puede añadir sin tocar arquitectura (es presentación pura).
- **Sin sistema de feature flags**: `domains.enabled` ya cubre el caso más simple (activar/desactivar un dominio entero). Un sistema de flags más fino (activar un scoring nuevo solo para un dominio, experimentar con variantes) es una buena idea para cuando el MVP funcione, no antes — añadirlo ahora sería exactamente el tipo de frente adicional que conviene evitar mientras el pipeline principal (fase 0-4 del roadmap) no esté validado.
- **Sin búsqueda manual**: el descubrimiento es 100% por swipe, no hay caja de búsqueda en el diseño. Si se añadiera en el futuro, el caché de `items` (por `domain_code` + `external_id`, compartido entre usuarios) ya soporta ese caso sin cambios — pero no es una funcionalidad que exista hoy en la app, así que no hay nada que resolver todavía.

---

## 13. Roadmap de implementación por fases

**Antes de la fase 1**: nada de Flask ni de Flutter todavía. Un script de terminal que ejecute `adapter → item → sqlite → text_for_vectorization → tfidf → recomendación → json` para un puñado de ítems reales de un solo dominio. El objetivo no es arquitectura, es responder a la pregunta que de verdad importa: *¿el algoritmo produce recomendaciones que tienen sentido?* Es mucho más barato descubrir que hace falta ajustar el enfoque en un script de 200 líneas que después de tener API y app Flutter construidas encima. Si el resultado es pobre, es el momento de decidir si hace falta enriquecer más los datos (sección 3.1) antes de seguir.

1. **Fundamentos backend**: esquema SQLite + repositories + `Item` genérico + `base_adapter` (interfaz) + interfaz `RecommendationEngine` (sección 3.1) + logging estructurado + manejo de errores estandarizado. Sin ningún dominio real todavía, solo con datos de fixture.
2. **Primer adapter real** (el que elijas primero) + endpoint de seed + endpoint de rating + job de recomendaciones. Validas el contrato end-to-end con un solo dominio — esto ya debería funcionar de forma muy parecida al script de la fase 0, solo que ahora detrás de una API real.
3. **Frontend fundamentos**: `ApiClient` + routing + pantalla de swipe (card stack + botones + cola local optimista) consumiendo el dominio del paso 2, con señal simple (`interested`/`rejected`) sin distinguir "ya lo conozco" todavía — swipe funcionando de punta a punta es el hito más importante.
4. **Segundo adapter**: si el paso 2-3 no obligó a tocar el motor ni la pantalla de swipe, la abstracción es correcta — este paso debería ser notablemente más rápido que el primero. Es la prueba de que el diseño funciona, y el hito que de verdad demuestra la idea central del proyecto.
5. **Filtros**: `domain_facets` + `item_attributes` + endpoint de esquema de filtros + panel de filtros dinámico en Flutter.
6. **Perfil**: pantalla de perfil + `user_profile` + `user_explicit_preferences` + fórmula de ponderación híbrida con los topes de peso ya fijados (sección 9).
7. **Señales completas + pantalla de Guardados**: toggle "ya lo conozco" en la tarjeta, `signal_weights`, pantalla de Guardados con bucle de confirmación (sección 7.3).
8. **Undo** + blacklist + estados de error en UI pulidos.
9. **Notificaciones locales** (sección 11).
10. **CI/CD** configurado (puede hacerse en paralelo desde la fase 1, mejor que dejarlo para el final).
11. **Dominios restantes** + memoria/documentación del curso.

Si llegas con solidez hasta el final de la fase 4, ya has demostrado lo esencial del proyecto: un único motor recomendando obras de dominios distintos con solo añadir un adapter. Todo lo de las fases 5-10 mejora la experiencia, pero no es lo que hace diferencial al proyecto — si el tiempo aprieta, es lo primero recortable, no el pipeline ni el segundo dominio.

---

## 14. Cambios necesarios en el repo actual (`Anime_recommender`)

Comparación entre lo que existe hoy y la arquitectura objetivo. Cuatro categorías: **ELIMINAR** (ya no aplica), **REESCRIBIR** (se mantiene el propósito, cambia la implementación), **ADAPTAR/REFERENCIA** (la lógica sirve de base pero se reestructura), **NUEVO** (no existe hoy).

### 14.1 Backend

| Archivo/carpeta actual | Acción | Motivo |
|---|---|---|
| `src/data/download_mal_list.py` | **ELIMINAR** | Dependencia de MAL que estamos quitando de raíz |
| `src/data/parse_xml.py` | **ELIMINAR** | Solo servía para parsear el export XML de MAL |
| `src/data/fetch_datasets.py` | **ELIMINAR** (lógica de referencia para los adapters) | Descarga el dataset base de anime; el equivalente nuevo es un `adapter` por dominio |
| `src/data/prepare_data.py` | **ADAPTAR/REFERENCIA** | La limpieza/normalización de datos es un buen punto de partida para los normalizadores de cada `adapter`, pero hay que generalizarla del esquema de columnas de anime al `Item` genérico |
| `src/model/train_model.py` | **REESCRIBIR**, dividiéndolo en `model/tfidf_engine.py` + `model/hybrid_scorer.py` | El núcleo (`TfidfVectorizer` + `TruncatedSVD` + `linear_kernel`, función `preprocess_data`) es reutilizable casi tal cual, generalizando de columnas anime-specific (`title`, `genres`...) a `Item.description`/`Item.tags`. La idea de **cachear la matriz de similitud** (`get_recommendations_for_user.py` la guarda en `.npz`) es buena y se mantiene, adaptada al nuevo esquema. Todo lo de `debug_log`/`print` se sustituye por el logging estructurado (sección 3.6). La lógica de `get_recommendations()` (score híbrido = similitud · vector de valoración + filtro por score mínimo) es el precedente directo de `hybrid_scorer.py`, generalizando `user_score` a las señales ponderadas de `signal_weights` |
| `src/services/get_recommendations_for_user.py` | **REESCRIBIR** como `services/recommendation_service.py`, ejecutado dentro de un job asíncrono (sección 3.5), no como script CLI/subproceso | Es el causante directo del timeout de 5 min: hoy `app.py` lo invoca con `subprocess.run(..., timeout=300)`. Pasa a ejecutarse en background y notificar vía `jobs` |
| `src/services/preload_dataset.py` | **ADAPTAR/REFERENCIA** | Idea reutilizable (precargar catálogo) pero ahora es responsabilidad del job `refresh_catalog` por dominio |
| `src/api/app.py` | **REESCRIBIR** completo como `api/routes/*.py` modularizado, prefijo `/api/v1`, endpoints parametrizados por `domain` en vez de hardcodeados a anime | Hoy mezcla rutas, invocación de subproceso y lógica de negocio en un único archivo de 315 líneas |
| `src/tests/*` | **REESCRIBIR** conforme se reescribe cada módulo que testean | Mantener `pytest.ini` como base |
| `data/*.csv`, `data/*.json` | **ELIMINAR** (no hay datos reales de usuario que migrar — es un único usuario de prueba) | Sustituidos por SQLite (sección 3.3); el catálogo se repuebla vía adapters |
| `notebooks/` | **MANTENER** sin tocar | Exploración, no forma parte del pipeline de producción |
| `requirements.txt` | **ACTUALIZAR** | Mantener `flask`, `flask-cors`, `pandas`, `numpy`, `scikit-learn`, `pytest`, `gunicorn`; añadir algo tipo `pydantic` (schemas/config), `apscheduler` o similar si se implementa el cron de refresco in-process |
| — | **NUEVO** | `src/adapters/` (`base_adapter.py` + uno por dominio), `src/repositories/` (una por tabla), `src/core/` (`logging_config.py`, `errors.py`, `config.py`, `db.py`), `src/model/item.py`, `src/api/schemas/`, `tests/contract/` |

### 14.2 Frontend (Flutter)

| Archivo/carpeta actual | Acción | Motivo |
|---|---|---|
| `lib/services/python_runner.dart` | **ELIMINAR** | Ya es vestigial por su propio comentario en el código ("se mantiene por compatibilidad"); no ejecuta Python, solo llama a `ApiService` |
| `lib/screens/login_screen.dart` (514 líneas) | **ELIMINAR** el concepto de "login con username de MAL** | Sustituido por selección de dominio + perfil local (`device_id`, sin credenciales externas). Puede reutilizarse la lógica de persistencia de `shared_preferences` como referencia para `user_profile` local |
| `lib/screens/anime_recommendations_screen.dart` (310 líneas) | **REESCRIBIR** como `features/recommendations/recommendations_screen.dart` (genérica, parametrizada por dominio, con card stack + swipe) | Hoy es específica de anime y usa `setState`, sin gestión de estado real |
| `lib/services/api_service.dart` | **REESCRIBIR** como `data/api/api_client.dart` (dio, con interceptor de logging + `request_id`) + repositorios concretos en `data/repositories/` | Hoy usa `http` plano, sin capa de abstracción, con `print()` de depuración |
| `lib/services/blacklist_service.dart` | **REESCRIBIR** como `data/repositories/blacklist_repository_impl.dart` | Mismo problema de logging y falta de abstracción que `api_service.dart` |
| `lib/widgets/blacklist_overlay.dart` (316 líneas) | **ADAPTAR/REFERENCIA** | Buen punto de partida visual para la pantalla de Guardados (sección 7.3), pero cambia de "overlay de blacklist" a "lista de confirmación pendiente" |
| `lib/main.dart` | **REESCRIBIR** | Añadir `ProviderScope` (Riverpod) y `go_router`; ya está bien encaminado (Material 3 correctamente configurado) |
| `pubspec.yaml` | **ACTUALIZAR** | Añadir `flutter_riverpod`, `dio`, `go_router`, `flutter_local_notifications`, `sqflite` o `hive` (cola local + caché), `uuid` (request_id); actualizar `flutter_lints` (hoy en `^2.0.0`); revisar si `shared_preferences`/`http` se mantienen o se sustituyen |
| `assets/localization.json` | **MANTENER**, sin usar activamente en el rediseño base | Ver sección 12 — no es requisito del rediseño, pero no hace falta borrarlo |
| — | **NUEVO** | `lib/core/` (`logging/`, `routing/`, `theme/`, `errors/`), `lib/domain/` (`models/`, `usecases/`), `lib/data/` (`api/`, `repositories/`), `lib/features/` (`domain_selection/`, `recommendations/`, `saved/`, `profile/`), `lib/core/notifications/` |
| `test/` | **NUEVO contenido real** | Hoy solo tiene el boilerplate por defecto de Flutter pese a que el README promete `flutter test` |

### 14.3 Orden recomendado de ejecución

Sigue el roadmap de la sección 13, pero a nivel de repo concreto: primero limpiar/reestructurar backend (14.1) sin romper el contrato que ya usa el frontend viejo, después migrar frontend (14.2) contra el backend ya reestructurado. No hacerlo a la vez — tener siempre un extremo estable mientras se reescribe el otro evita quedarte con la app completamente rota a mitad de refactor.
