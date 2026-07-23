# src/adapters/registry.py
"""Registro de qué adapter de Python implementa cada dominio — detalle interno de
código, separado de qué dominios existen como concepto de producto (tabla `domains`
en BD, ver src/repositories/domain_repository.py, que no importa nada de este
módulo). Un dominio nuevo = una entrada más aquí (ver
docs/decisions/0001-item-generico-y-adapters.md)."""

from src.adapters.base_adapter import BaseAdapter
from src.adapters.rawg_adapter import RawgAdapter
from src.adapters.tmdb_adapter import TmdbAdapter

ADAPTER_REGISTRY: dict[str, type[BaseAdapter]] = {
    "games": RawgAdapter,
    "movies": TmdbAdapter,
}


def get_adapter_class(domain_code: str) -> type[BaseAdapter] | None:
    return ADAPTER_REGISTRY.get(domain_code)


def is_domain_supported(domain_code: str) -> bool:
    return domain_code in ADAPTER_REGISTRY
