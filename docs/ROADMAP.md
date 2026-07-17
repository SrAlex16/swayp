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

## Limpieza pendiente de rebranding (Anime_recommender → Swayp)

- `pubspec.yaml` → cambiar `name:` a `swayp` en el proyecto Flutter
- `applicationId` / bundle id de Android e iOS si en algún momento se generan builds firmados
- Revisar README y cualquier referencia suelta a "Anime Recommender" en código o documentación
