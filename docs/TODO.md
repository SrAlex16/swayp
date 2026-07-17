# To-do — corto plazo (Fase 0: validar el motor sin API ni Flutter)

- [x] Definir el modelo `Item` (dataclass/pydantic)
- [x] Implementar `base_adapter.py` (interfaz) y un primer adapter real
- [x] Esquema mínimo de SQLite para `items` (solo lo necesario para esta fase)
- [x] Construir `text_for_vectorization` en el adapter elegido
- [x] Implementar `TFIDFRecommendationEngine` (interfaz `RecommendationEngine` + primera implementación)
- [x] Script `recommend.py` de terminal: usuario de prueba con gustos declarados → top N recomendaciones legibles
- [ ] Validar manualmente con 2-3 perfiles de prueba distintos si las recomendaciones tienen sentido
- [ ] Decidir si hace falta enriquecer más los datos antes de pasar a la Fase 1
