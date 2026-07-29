
# Swayp

Recomendador multi-dominio estilo swipe (Tinder-like): descubre películas, videojuegos,
libros y más, con un único motor de recomendación agnóstico de dominio. Cada dominio se
integra mediante un `adapter` propio (ver `docs/ARCHITECTURE.md`), sin tocar el motor ni
la mayoría de la UI.

## Estado actual

El proyecto ya cuenta con un backend funcional y validado:

- API Flask con dominios, seed, ratings, jobs, recomendaciones, perfil, preferencias y blacklist.
- Motor TF-IDF + SVD con shrinkage por volumen de ratings.
- Modelo de señales simplificado a `interested`, `rejected` y `skipped`.
- Suite de tests backend completa ejecutándose correctamente en el entorno del proyecto.

La app Flutter sigue en fase de scaffolding; el siguiente paso es conectar la UI real con
la API ya existente.

Para el diseño completo de la arquitectura objetivo (backend, frontend, esquema de datos,
contrato de API, UX y decisiones de alcance), ver [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).

## 🚀 Instalación y uso

**Requisitos**: Python 3.11+ y pip.

```bash
git clone https://github.com/SrAlex16/swayp
cd swayp
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Configura tus variables de entorno si necesitas conectar adapters externos, por ejemplo:

```bash
cp .env.example .env
```

Ejecuta la API:

```bash
python run.py
```

Para poblar el catálogo local y probar el motor de recomendación de forma manual:

```bash
python scripts/populate_catalog.py --count 200
python recommend.py --user test --likes "Elden Ring" "Dark Souls" "Hollow Knight"
```

`recommend.py` también admite `--debug` (desglose de `similarity_score`,
`community_score_normalizado` y los términos TF-IDF compartidos por cada
recomendación) e `--inspect-text` (imprime el `text_for_vectorization` guardado para
un título, sin pasar por el motor):

```bash
python recommend.py --user test --likes "Elden Ring" "Dark Souls" --debug
python recommend.py --inspect-text "Elden Ring"
```

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

