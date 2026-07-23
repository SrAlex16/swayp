# ADR-0005: Conjunto de reglas de ruff — por defecto, sin reglas de estilo adicionales

**Fecha**: 2026-07-21
**Estado**: Aceptada

## Contexto
Antes de montar el workflow de CI/CD (docs/ARCHITECTURE.md sección 6) hacía falta
elegir una herramienta de linting/formato y decidir qué conjunto de reglas aplicar.
Se corrió `ruff check .` sobre el código real (`src/`, `tests/`, `scripts/`,
`recommend.py`, `run.py`, 58 archivos) como diagnóstico antes de decidir nada: con el
conjunto de reglas por defecto de ruff (`E4`/`E7`/`E9` de pycodestyle + `F` de
Pyflakes), el resultado fue `All checks passed!` — 0 errores.

## Decisión
Nos quedamos con el conjunto de reglas **por defecto** de ruff, sin añadir reglas de
estilo adicionales (ej. `I` para orden de imports, `UP` para sintaxis moderna, `D`
para docstrings...) por ahora. Este conjunto ya protege contra errores reales:
sintaxis inválida, imports sin usar, variables sin usar — sin añadir fricción de
estilo sobre un código que, verificado con el diagnóstico, ya pasa limpio.

`ruff format .` sí se aplicó sobre todo el código (29 de 60 archivos necesitaban
reformatearse), como formateador único del proyecto — confirmado con la suite de
tests completa que el formateo no cambia comportamiento.

## Alternativas consideradas
- Añadir reglas de estilo adicionales (`I`, `UP`, `B`, `SIM`...) desde el principio:
  descartado por ahora. Añadir un conjunto de reglas más estricto sin ninguna
  necesidad concreta detectada (el diagnóstico ya daba 0 errores) sería fricción
  añadida sin un problema real que resolver — se puede ampliar más adelante si surge
  un caso concreto que lo justifique.
- No lintar en absoluto / dejarlo para más adelante: descartado. El CI/CD ya se está
  montando en este bloque, y el coste de incluir un lint mínimo (que ya pasa limpio)
  es prácticamente cero comparado con el valor de que el gate exista desde el primer
  workflow, en vez de añadirlo después como una migración aparte.

## Consecuencias
`ruff check .` y `ruff format --check .` forman parte del pipeline de CI
(`.github/workflows/backend-ci.yml`) junto a `pytest -v`. Si en el futuro se detecta
un problema concreto que un conjunto de reglas más estricto habría evitado, es una
decisión aislada de ampliar `ruff.toml`, no de migrar de herramienta.
