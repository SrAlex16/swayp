# ADR-0001: Item genérico + patrón adapter por dominio

**Fecha**: 2026-07-17
**Estado**: Aceptada

## Contexto
El proyecto original recomendaba solo anime, dependiendo de que el usuario tuviera cuenta pública de MyAnimeList. Se decidió generalizar a un recomendador multi-dominio (películas, libros, videojuegos, board games...) elegible por el usuario.

## Decisión
Se define un esquema `Item` genérico (title, description, text_for_vectorization, tags, community_score, image_url...) al que cada dominio se normaliza mediante un `adapter` propio (TMDB, RAWG, Open Library, BGG...). El motor de recomendación opera solo sobre `Item`, sin conocer de qué dominio proviene.

## Alternativas consideradas
- App/tabla distinta por dominio: descartado, duplica lógica y no escala a nuevos dominios.
- Modelo de datos ancho con columnas específicas de cada dominio: descartado, acopla el motor a los dominios existentes.

## Consecuencias
Añadir un dominio nuevo implica escribir un adapter, no tocar el motor ni la mayoría de la UI. A cambio, cada adapter debe normalizar datos heterogéneos a un esquema común (ver diseño de `text_for_vectorization` en ARCHITECTURE.md).

## Validación (Fase 2)

El segundo adapter (`TmdbAdapter`, dominio películas) se implementó sin modificar `src/model/` (Item, engine, tfidf_engine), `src/api/` ni `src/services/` — confirmado con `git status` antes del commit. Es la prueba empírica de que la decisión de esta ADR se sostiene con un segundo caso real, no solo con el diseño sobre el papel.
