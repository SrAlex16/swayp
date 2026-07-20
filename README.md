
# Swayp

Recomendador multi-dominio estilo swipe (Tinder-like): descubre películas, videojuegos,
libros y más, con un único motor de recomendación agnóstico de dominio. Cada dominio se
integra mediante un `adapter` propio (ver `docs/ARCHITECTURE.md`), sin tocar el motor ni
la mayoría de la UI.

Sucesor del proyecto anterior (Anime Recommender, centrado en un solo dominio y
dependiente de una cuenta pública de MyAnimeList). El código legacy relevante como
referencia visual se conserva en [`legacy_reference/`](./legacy_reference).

## Estado actual

El proyecto está en la **Fase 0** del roadmap de implementación (ver
[`docs/TODO.md`](./docs/TODO.md) y [`docs/ROADMAP.md`](./docs/ROADMAP.md)): validando el
motor de recomendación (TF-IDF + SVD) con un único dominio (videojuegos, vía la API de
RAWG) desde un script de terminal, sin API REST ni app Flutter todavía.

Para el diseño completo de la arquitectura objetivo (backend, frontend, esquema de
datos, contrato de API...), ver [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).

## 🚀 Instalación y uso (Fase 0)

**Requisitos**: Python 3.11+ y pip.

```bash
git clone https://github.com/SrAlex16/swayp
cd swayp
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Configura tu API key de RAWG en un archivo `.env` en la raíz:

```
RAWG_API_KEY=tu_api_key
```

Puebla el catálogo local y prueba el motor de recomendación:

```bash
python scripts/populate_catalog.py --count 200
python recommend.py --user test --likes "Elden Ring" "Dark Souls" "Hollow Knight"
```

`recommend.py` también admite `--debug` (desglosa `similarity_score`,
`community_score_normalizado` y los términos TF-IDF compartidos por cada
recomendación) e `--inspect-text` (imprime el `text_for_vectorization` guardado para
un título, sin pasar por el motor):

```bash
python recommend.py --user test --likes "Elden Ring" "Dark Souls" --debug
python recommend.py --inspect-text "Elden Ring"
```

> Las instrucciones de instalación y uso de la API REST y de la app Flutter están
> pendientes de reescribir conforme avancen las fases 1-3 del roadmap.

## 🧪 Tests

```bash
python -m pytest
```

> Nota: la suite de tests actual (`src/tests/`) está pendiente de reescribir — testeaba
> el pipeline del proyecto anterior (anime/MAL), cuyos archivos ya se han eliminado.

## 📄 Licencia

[Licencia de uso personal / Personal Use License](https://github.com/SrAlex16/swayp/blob/main/LICENSE.md#licencia-de-uso-personal--personal-use-license)

## 👨🏼‍💼 Authors

- [@SrAlex16](https://github.com/SrAlex16)

## 🔗 Links
[![Portfolio](https://img.shields.io/badge/my_portfolio-1?style=for-the-badge&logo=ko-fi&logoColor=black)](https://www.aletm.com)

[![LinkedIn](https://img.shields.io/badge/linkedIn-1DA1F2?style=for-the-badge&logo=linkedin&logoColor=white)](https://linkedin.com/)

