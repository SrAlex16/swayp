# src/model/item.py
from dataclasses import dataclass, field


@dataclass
class Item:
    """Ítem genérico del catálogo, agnóstico de dominio (ver docs/ARCHITECTURE.md, sección 3.1)."""

    external_id: str
    title: str
    description: str
    text_for_vectorization: str
    domain: str = "games"
    tags: list[str] = field(default_factory=list)
    community_score: float = 0.0
    image_url: str | None = None
    external_url: str | None = None
    adapter_version: str = ""
    enrichment_version: str = ""
