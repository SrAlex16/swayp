# src/model/domain.py
from dataclasses import dataclass


@dataclass
class Domain:
    code: str
    display_name: str
    enabled: bool
