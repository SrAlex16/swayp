# ADR-0003: Cada adapter filtra su propio ruido de metadatos, no hay limpieza genérica

**Fecha**: 2026-07-17
**Estado**: Aceptada

## Contexto
Durante la validación de la Fase 0 (ver `docs/fase0-validacion.md`) se detectó que
RAWG mezcla, dentro del mismo campo de tags, señal de género/temática real (ej. "Dark
Fantasy", "Metroidvania") con metadatos propios de la ficha de Steam/plataforma (ej.
"Steam Achievements", "Full controller support", "Co-op") que no aportan nada para
medir afinidad de gustos y, en la práctica, diluían y contaminaban la señal real.

## Decisión
Cada `adapter` mantiene su propia `TAG_DENYLIST` (u equivalente) con los términos de
ruido específicos de su fuente de datos, aplicada solo al construir
`text_for_vectorization` — nunca al campo `tags` de `Item`, que se conserva completo
para otros usos (mostrar en UI, filtros de la sección 8 de ARCHITECTURE.md).

## Alternativas consideradas
- Lista de denylist genérica compartida entre adapters: descartada. Cada fuente de
  datos tiene su propio vocabulario de ruido (Steam en el caso de RAWG; previsiblemente
  otros patrones distintos en TMDB, Open Library, BGG cuando se añadan) — una lista
  compartida o bien se queda corta para una fuente, o crece de forma desordenada
  mezclando conceptos de fuentes distintas sin relación entre sí.
- Limpieza automática vía heurística general (ej. descartar tags con "steam" en el
  nombre): descartada por ahora — más frágil y menos auditable que una lista explícita
  y documentada, aunque requiera mantenimiento manual al añadir cada adapter nuevo.

## Consecuencias
Añadir un adapter nuevo implica revisar sus tags reales (no asumir que se comportan
como RAWG) y construir su propia denylist si hace falta, siguiendo el mismo patrón:
filtrar solo del texto de vectorización, documentar el motivo con casos reales
detectados, no heurísticas genéricas sin verificar.

El adapter de TMDB (Fase 2) no necesitó `TAG_DENYLIST` — su heterogeneidad es distinta
(campos de producción separados, no tags mezclados). Se detectó un caso menor de ruido
de metadata técnica (keywords "duringcreditsstinger"/"aftercreditsstinger", marcador de
escena post-créditos) con peso bajo y sin impacto observable en el ranking — no se
actúa por ahora, queda anotado por si crece con más datos.
