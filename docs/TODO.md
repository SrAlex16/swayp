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
- [ ] Probar el flujo completo (seed → ratings → job → resultado) contra el servidor Flask real antes de dar la Fase 1 por cerrada
