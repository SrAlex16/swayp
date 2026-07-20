# src/model/user.py
from dataclasses import dataclass


@dataclass
class User:
    id: int
    device_id: str
    created_at: str
