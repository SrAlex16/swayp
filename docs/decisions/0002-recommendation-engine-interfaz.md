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

Limitación conocida observada en la práctica durante la Fase 0: el TF-IDF confunde coincidencias léxicas sin relación semántica. Con un perfil souls-like (Dark Souls, Elden Ring, Sekiro), el motor recomendó *Cuphead* entre los primeros resultados por compartir el término "souls" — en el perfil se refiere a la saga Dark Souls, en Cuphead a una mecánica de recolección de almas sin relación temática real. No es un bug a arreglar (la mitigación de ruido léxico de esta fase, ver `src/model/tfidf_engine.py`, ya reduce estos casos pero no los elimina): es la limitación de fondo de un enfoque léxico sin comprensión semántica, y el motivo de contemplar `EmbeddingRecommendationEngine` como alternativa futura (ver ROADMAP.md).
