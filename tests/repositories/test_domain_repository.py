# tests/repositories/test_domain_repository.py
from src.repositories import domain_repository


def test_get_enabled_devuelve_los_2_dominios_sembrados_por_defecto(temp_db):
    domains = domain_repository.get_enabled()

    assert {(domain.code, domain.display_name) for domain in domains} == {
        ("games", "Videojuegos"),
        ("movies", "Películas"),
    }
    assert all(domain.enabled for domain in domains)
