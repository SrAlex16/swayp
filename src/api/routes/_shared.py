# src/api/routes/_shared.py
"""Helpers compartidos entre blueprints de src/api/routes/ (no es un blueprint en sí)."""

from src.core.errors import NotFoundError
from src.repositories import domain_repository


def require_enabled_domain(domain_code: str) -> None:
    """Lanza NotFoundError si domain_code no existe o no está habilitado en la tabla
    `domains`, en vez de dejar que la ruta siga adelante silenciosamente contra un
    catálogo vacío para un dominio que no existe."""
    enabled_codes = {domain.code for domain in domain_repository.get_enabled()}
    if domain_code not in enabled_codes:
        raise NotFoundError("Dominio no encontrado")
