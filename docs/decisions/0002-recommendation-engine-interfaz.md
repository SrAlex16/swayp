# ADR-0002: RecommendationEngine como interfaz, no como implementación concreta

**Fecha**: 2026-07-17
**Estado**: Aceptada

## Contexto
El algoritmo de partida (heredado de la versión anterior del proyecto) es TF-IDF + SVD + similitud coseno. Es un enfoque content-based con limitaciones conocidas (depende de la calidad del texto descriptivo disponible).

## Decisión
Se define una interfaz `RecommendationEngine` con un método de scoring sobre `Item` + perfil de usuario. La primera implementación es `TFIDFRecommendationEngine`. El resto del sistema depende de la interfaz, no de la implementación concreta.

## Alternativas consideradas
- Acoplar el TF-IDF directamente a los servicios: descartado, dificulta migrar a otro enfoque (embeddings) sin reescribir capas superiores.

## Consecuencias
Cambiar de algoritmo en el futuro es sustituir una implementación, no rediseñar el sistema. Ver ROADMAP.md.
