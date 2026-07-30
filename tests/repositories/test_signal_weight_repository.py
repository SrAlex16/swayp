# tests/repositories/test_signal_weight_repository.py
from src.repositories import signal_weight_repository


def test_get_all_devuelve_los_2_valores_sembrados_por_defecto(temp_db):
    weights = signal_weight_repository.get_all()

    assert weights == {
        "rejected": -1.0,
        "interested": 0.3,
    }
