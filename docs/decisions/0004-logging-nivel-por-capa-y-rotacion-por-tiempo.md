# ADR-0004: Nivel de log por capa (no por endpoint) y rotación por tiempo con retención

**Fecha**: 2026-07-20
**Estado**: Aceptada

## Contexto
La infraestructura de logging estructurado (JSON, `request_id` vía contextvars)
existía desde el Bloque A de la Fase 1, pero solo `job_service.py` la usaba de
verdad. Hacía falta decidir qué nivel de log usar en cada capa, si loguear también
las operaciones de lectura (no solo escrituras), y cómo evitar que los archivos de
log crecieran sin límite.

## Decisión
- Criterio de nivel por capa: `DEBUG` para el detalle interno de repositories y
  peticiones a APIs externas (incluidas las exitosas, no solo los fallos); `INFO`
  para eventos de negocio en adapters/servicios/rutas HTTP (incluidas las lecturas de
  base de datos, por decisión explícita del usuario, sabiendo que genera más volumen
  que loguear solo escrituras); `WARNING` para fallos controlados (`AppError`,
  fallo de llamada externa); `ERROR` para excepciones no controladas, con traceback
  completo (`exc_info=True`).
- El log de nivel HTTP (`request_completed`: método, ruta, status, `duration_ms`) vive
  en `before_request`/`after_request` de Flask, no en cada ruta — así cualquier
  endpoint nuevo queda cubierto automáticamente sin depender de que se loguee a mano.
  Solo se loguean metadatos, nunca el body de la request/response (decisión explícita:
  evitar que datos de negocio, aunque sean de bajo riesgo como `device_id`, queden
  fáciles de correlacionar con comportamiento en un log que podría compartirse).
- Rotación con `logging.handlers.TimedRotatingFileHandler` de la librería estándar,
  con intervalo y número de copias retenidas configurables por `.env`
  (`LOG_ROTATION_INTERVAL`, `LOG_RETENTION_COUNT`), en paralelo al `StreamHandler` de
  consola ya existente.

## Alternativas consideradas
- Job de limpieza periódico aparte (cron o similar) para borrar logs antiguos:
  descartado. `TimedRotatingFileHandler` ya resuelve rotación + borrado automático de
  archivos rotados más allá de la retención configurada, sin necesitar
  infraestructura adicional ni un proceso programado propio.
- Loguear el body completo de requests/responses: descartado por ahora, para no
  acoplar el log a la evolución del contrato de la API y evitar exponer más datos de
  los necesarios en los archivos de log.

## Consecuencias
Con `LOG_LEVEL=INFO` (default), los logs de lectura de repositories/adapters quedan
silenciados por defecto (viven en `DEBUG`); el volumen de `INFO` en producción normal
es el de eventos de negocio + requests HTTP, no el de cada `SELECT`. Si el volumen de
`logs/swayp.log` se vuelve incómodo de revisar con el uso real, la vía más simple es
bajar la retención (`LOG_RETENTION_COUNT`) o el intervalo de rotación, sin tocar
código.
