# To-do — estado actual del proyecto

Este documento recoge el estado real del backend y la ruta de trabajo más reciente. La documentación anterior mezclaba fases históricas con ideas futuras; aquí se deja una vista más útil para el trabajo actual.

## Estado de implementación

### Backend Python
- [x] Motor de recomendación TF-IDF + SVD implementado y validado.
- [x] API REST con dominios, seed, ratings, jobs, preferencias, perfil y blacklist.
- [x] Modelo de señales simplificado a dos estados: `interested` y `rejected`.
- [x] Estado neutral `skipped` para omitir tarjetas sin convertirlas en señal positiva o negativa.
- [x] Shrinkage basado en el total de ratings del usuario por dominio, con la fórmula $w_{explicit} = \max(0.1, 1 - total\_ratings/50)$.
- [x] Reset del algoritmo: `DELETE /api/v1/domains/<domain_code>/ratings` borra todos los ratings del usuario en ese dominio (incluidos los `interested`, vacía Guardados), preservando preferencias explícitas y blacklist.
- [x] Suite de tests backend completa en verde.

### Frontend Flutter
- [x] Rebranding a Swayp completado.
- [x] Proyecto Flutter arrancando con dependencias base y build real de Android.
- [x] Limpieza del flujo de Guardados: eliminado el repository legacy de `pending-confirmation` y ahora el listado de Guardados consume `SavedRepository`.
- [ ] Arquitectura de carpetas y pantallas reales aún pendiente de implementar.

## Progreso verificado

### Backend
- [x] Endpoint de ratings acepta `interested`, `rejected` y `skipped`.
- [x] `GET /api/v1/domains/<domain_code>/pending-confirmation` sigue devolviendo los ratings `interested` para la lista de Guardados.
- [x] Recomendaciones se calculan con shrinkage por volumen de ratings.
- [x] Tests de integración y unitarios ejecutados con éxito.

### CI/CD
- [x] Workflow de backend CI configurado para lint, formato y tests.

## Trabajo pendiente prioritario

1. Implementar la capa de frontend real sobre la API existente.
2. Definir la arquitectura de carpetas Flutter (`core`, `data`, `domain`, `features`).
3. Conectar la pantalla de swipe con los endpoints de seed, ratings y recomendaciones.
4. Implementar la pantalla de Guardados y el perfil real sobre el backend actual.
5. Revisar la documentación de producto y la UI cuando el frontend avance.

## Notas de producto

- La decisión de producto actual es mantener un modelo de señales simple y explícito para el usuario: aceptar/rechazar/omitir.
- Guardados sigue siendo una vista simple de `interested`; no existe un flujo de confirmación posterior.
- El estado `skipped` sirve para avanzar sin introducir ruido en el perfil de recomendación.
