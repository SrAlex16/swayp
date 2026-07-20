# Fase 0 — Validación del motor de recomendación

Resumen narrativo de la sesión de validación y tuning del motor (TF-IDF + SVD),
dominio de videojuegos (RAWG), catálogo de 200 ítems. Ver también CHANGELOG.md
(resumen técnico) y ADR-0002 (decisión de diseño que motivó esta validación).

## Objetivo

Validar, antes de construir API ni Flutter, si `TFIDFRecommendationEngine` produce
recomendaciones con sentido dado un perfil de gustos declarado, usando el criterio de
aceptación humano definido en el roadmap: "si al leer la lista de recomendaciones
piensas que tiene sentido, el motor está validado".

## Configuración inicial (heredada de Anime_recommender sin ajustar)

El código se implementó replicando fielmente el enfoque del proyecto anterior, sin
reajustar sus parámetros al nuevo catálogo: `TfidfVectorizer` sin límite de vocabulario
(`max_features`) y `TruncatedSVD` con hasta 100 componentes — valores razonables para
un catálogo de miles de animes, sin validar si seguían siéndolo para un catálogo de
prueba de 200 juegos.

## Ronda 1 — primera ejecución

Perfil de prueba: souls-like (Elden Ring, Dark Souls III, Hollow Knight).

Resultado: solo 1 de 10 recomendaciones (Bloodborne) era un acierto claro; el resto
mezclaba ruido evidente (GTA III, Life is Strange, This War of Mine — sin relación con
el perfil). Varios scores finales idénticos (0.30 repetido), señal de que la similitud
de contenido era casi nula y el 15% de peso de `community_score` estaba decidiendo el
ranking por popularidad, no por afinidad real.

## Ronda 2 — sobreajuste por exceso de componentes SVD

Diagnóstico: con 200 documentos y hasta 100 componentes SVD, el modelo tenía casi un
componente por cada 2 documentos — capacidad suficiente para memorizar idiosincrasias
de texto de cada sinopsis en vez de generalizar patrones de género.

Cambios: `max_features=2000` en el TF-IDF (antes sin límite); componentes SVD ajustados
a `catálogo/5` con mínimo 10 y techo 100 (40 componentes para el catálogo de 200 ítems,
antes ~100).

Resultado: mejora sustancial. similarity_score de Bloodborne para el perfil souls-like
subió de 0.375 a 0.740. Perfil de mundo abierto (GTA V/RDR2): top 5 limpio, sin
intrusos. Perfil indie (Hollow Knight/Terraria): resultados bastante más coherentes.

## Ronda 3 — coincidencia léxica sin relación semántica (caso Cuphead)

Con `--debug` activo se detectó que Cuphead aparecía en el top de un perfil souls-like
por compartir el término "souls" con el perfil — pero en el texto de Cuphead la palabra
aparece dos veces sin relación con la saga Dark Souls: una vez como comparación de
marketing de dificultad ("2D Dark Souls as the fans refer to the difficulty of this
one"), y otra como parte de la trama ("bring the master souls of its debtors").
Confirmado con `--inspect-text`.

No se trata como bug: es la limitación de fondo de un enfoque léxico (bag-of-words) sin
comprensión semántica — ver ADR-0002, sección "Consecuencias".

## Ronda 4 — ruido de metadatos de plataforma mezclado con señal de género

Al repetir x3 el bloque de géneros/tags frente a la sinopsis (para compensar que la
prosa libre tiene más palabras y diluye la señal estructurada), apareció un efecto
secundario: Bloodborne cayó del top 5 del perfil souls-like porque RAWG mezcla, dentro
del mismo campo `tags`, tanto descriptores de género/temática (ej. "Dark Fantasy",
"Exploration") como características de la ficha de Steam (ej. "Steam Achievements",
"Steam Cloud", "Full controller support") — y Bloodborne, al ser exclusivo de
PlayStation, no tiene ninguno de esos tags de Steam, así que su lista de tags queda más
corta y con menos repeticiones útiles que la de juegos con más "ruido" de plataforma
que repetir.

Confirmado inspeccionando directamente los tags crudos en la base de datos.

Cambio: `TAG_DENYLIST` en `RawgAdapter` filtra del `text_for_vectorization` (no del
campo `tags` de `Item`, que se conserva completo para otros usos) los términos de
plataforma/tienda: Steam Achievements, Steam Cloud, Steam Leaderboards, Steam Workshop,
Valve Anti-Cheat enabled, steam-trading-cards, controller support (todas sus variantes),
Cross-Platform Multiplayer, Captions available, exclusive, true exclusive, vr mod, Free
to Play, In-App Purchases, y (ronda 5) Co-op, Cooperative, Multiplayer, Singleplayer.

Resultado: similarity_score de Bloodborne para el perfil souls-like: 0.560 → 0.664,
recupera el puesto #1 con términos compartidos genuinamente temáticos (souls, dark,
rpg, exploration, fantasy).

## Ronda 5 — sesgo de diversidad del catálogo de prueba

Se amplió `TAG_DENYLIST` con `Co-op`, `Cooperative`, `Multiplayer`, `Singleplayer`
(mismo criterio que la Ronda 4: características técnicas/de modo de juego, no género).
En su momento se afirmó que Bloodborne se mantenía en el puesto #1 del perfil
souls-like tras este cambio — **esa afirmación no se verificó con el desglose
`--debug` correspondiente** y resultó ser incorrecta.

Estado final verificado (`recommend.py --debug`, perfil souls-like: Elden Ring, Dark
Souls III, Hollow Knight):

1. Dead Cells (0.70)
2. Terraria (0.69)
3. Hades (0.68)
4. Bastion (0.65)
5. Fallout 4 (0.65)
6. Ori and the Blind Forest (0.63)
7. Skyrim (0.63)
8. Cuphead (0.63, con "souls" como término compartido — caso ya documentado en ADR-0002)
9. Undertale (0.61)
10. Bloodborne (0.60)

El perfil de mundo abierto (GTA V/RDR2) seguía dando resultados cuestionables (Watch
Dogs, Monster Hunter: World) incluso tras limpiar el ruido de plataforma. Medido
directamente: en el catálogo de 200 juegos (los "más añadidos" de RAWG, sesgados hacia
AAA de acción), términos como "Action" (83%), "Singleplayer" (90%), "Atmospheric"
(76%), "Open World" (45%) aparecen en una fracción tan alta del catálogo que dejan de
discriminar gustos.

Diagnóstico: no es un problema del motor, es un problema de composición del catálogo de
prueba (poco diverso por género). Documentado en `docs/ROADMAP.md` como mejora futura
de `scripts/populate_catalog.py` (sampleo estratificado por género), no como bloqueante
para la Fase 0.

## Veredicto final

Fase 0 validada, con matices. El perfil indie da recomendaciones limpias y
explicables. El perfil de mundo abierto es razonable, con la causa raíz del sesgo de
catálogo ya identificada y documentada como limitación conocida, no del motor. El
perfil souls-like es temáticamente coherente (sin ruido burdo tipo lo visto en la
Ronda 1) pero no está óptimamente ordenado: el match más evidente del catálogo
(Bloodborne, mismo estudio y subgénero que Dark Souls/Elden Ring) queda en la posición
#10 en vez de encabezar la lista, y el caso de coincidencia léxica sin relación
semántica (Cuphead, ver ADR-0002) reaparece en el top 10. Se aplica el mismo criterio
de parada que en rondas anteriores: no seguir ajustando parámetros del motor sobre
este catálogo concreto para evitar sobreajustar a sus peculiaridades, aceptando esta
limitación de ranking como conocida y documentada.

## Lecciones para las siguientes fases (y siguientes adapters)

1. Los parámetros de vectorización (`max_features`, componentes SVD, `max_df`) deben
   ajustarse en proporción al tamaño real del catálogo, no heredarse de otro contexto.
2. Cada fuente de datos externa (RAWG, y previsiblemente TMDB/Open Library/BGG cuando
   se añadan) mezcla señal de género/temática real con metadatos propios de la
   plataforma/tienda de origen — cada adapter necesita su propia lista de términos a
   filtrar, no hay una limpieza genérica válida para todos los dominios (ver ADR-0003).
3. La calidad de las recomendaciones depende tanto del algoritmo como de la diversidad
   del catálogo — merece la pena medir la distribución de tags del catálogo antes de
   dar por buena una sesión de validación.
4. Herramientas de diagnóstico (`--debug`, `--inspect-text`) fueron imprescindibles:
   sin desglose de scores ni inspección directa del texto, varios de estos hallazgos
   habrían quedado como "el algoritmo no funciona bien" sin causa identificada.
5. Verificar siempre con datos reales antes de aceptar una afirmación de
   "comportamiento estable" — en la Ronda 5 se aceptó una afirmación sin el desglose
   `--debug` correspondiente, lo que generó ambigüedad más tarde sobre cuál era el
   estado final verdadero de la Fase 0.
