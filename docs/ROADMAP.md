# Roadmap — ideas a futuro

Funcionalidades y mejoras pospuestas conscientemente (no olvidadas). Cuando se aborde alguna, se mueve a TODO.md y se referencia el ADR correspondiente si aplica.

- Push notifications vía FCM (v2) — solo si se necesita que el backend dispare notificaciones; v1 usa notificaciones locales.
- Recomendación colaborativa (comparar gustos entre usuarios) — requiere una base de usuarios reales suficiente.
- Multi-idioma ES/EN — capa de presentación, no bloqueante para el MVP.
- Sistema de feature flags más fino (activar un scoring/algoritmo nuevo solo para un dominio concreto).
- Búsqueda manual dentro de un dominio — el caché de `items` ya lo soportaría sin cambios de esquema.
- `EmbeddingRecommendationEngine` (Sentence Transformers) como implementación alternativa de `RecommendationEngine`, sustituyendo o complementando TF-IDF sin tocar servicios ni controllers.
- Almacenamiento incremental de vectores + publicación de modelo estilo blue-green — descartado por escala actual (catálogo pequeño); revisar si el catálogo crece a decenas de miles de ítems.
- Dominios adicionales (ej. podcasts como dominio propio, no como subtipo de música, si se decide añadir).
- Login real con sync multi-dispositivo (hoy identidad solo por `device_id` local).
- Mejorar `scripts/populate_catalog.py` para samplear el catálogo de RAWG de forma diversa por género (ej. estratificado, no solo por popularidad/`-added`). Detectado en Fase 0: con los 200 juegos más populares, términos como Action (83%), Singleplayer (90%) u Open World (45%) aparecen en una fracción tan alta del catálogo que dejan de discriminar gustos — es un problema de composición del catálogo de prueba, no del motor de recomendación.

## Limpieza pendiente de rebranding (Anime_recommender → Swayp) — RESUELTO

`frontend/anime_recommender_app/` renombrado a `frontend/swayp/` (`git mv`, historial conservado). `pubspec.yaml` (`name: swayp`), `applicationId`/namespace de Android y `PRODUCT_BUNDLE_IDENTIFIER` de iOS/macOS actualizados a `com.sralex16.swayp` (antes `com.example.anime_recommender_app`), binario/nombre de app en Linux y Windows también renombrados. Sin referencias sueltas a "anime_recommender"/"Anime Recommender" en código o config de build (`README.md`, `web/manifest.json`, `AndroidManifest.xml`, `Info.plist`). Queda pendiente, fuera de este bloque: `assets/localization.json` conserva strings del dominio de anime (login/blacklist) porque son contenido de la app vieja, no branding — se sustituirá al construir las pantallas reales (ver sección "Frontend Flutter — fundamentos" en docs/TODO.md).
